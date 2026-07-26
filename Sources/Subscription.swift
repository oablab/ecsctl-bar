import SwiftUI
import StoreKit

// MARK: - Subscription Manager (StoreKit 2)

/// Gates the Mac App Store build behind a $0.99/month auto-renewable
/// subscription. Non-sandboxed builds (built from source / Developer ID)
/// are never gated.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    /// Auto-renewable subscription product (configure in App Store Connect
    /// with this exact id, $0.99/month).
    static let productID = "dev.pahud.ecsctlbar.monthly"

    /// Only the sandboxed (MAS) build requires a subscription.
    /// Dev escape hatch for prototype testing before the ASC product exists:
    /// `defaults write dev.pahud.ecsctl-bar devBypassPaywall -bool true`
    static let gatingRequired =
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        && !UserDefaults.standard.bool(forKey: "devBypassPaywall")

    enum State: Equatable {
        case checking
        case subscribed
        case notSubscribed
        case unavailable(String)   // products failed to load (no ASC record / offline)
    }

    @Published var state: State = SubscriptionManager.gatingRequired ? .checking : .subscribed
    @Published var product: Product?
    @Published var busy = false

    private var updatesTask: Task<Void, Never>?

    private init() {
        guard Self.gatingRequired else { return }
        updatesTask = Task { [weak self] in
            // Handle renewals / revocations / purchases from other devices.
            for await update in Transaction.updates {
                if case .verified(let txn) = update {
                    await txn.finish()
                }
                await self?.refreshEntitlement()
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil, case .checking = state {
                state = .unavailable("subscription product not found")
            }
        } catch {
            if case .checking = state {
                state = .unavailable(error.localizedDescription)
            }
        }
    }

    func refreshEntitlement() async {
        guard Self.gatingRequired else { return }
        var active = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let txn) = entitlement,
               txn.productID == Self.productID,
               txn.revocationDate == nil {
                active = true
            }
        }
        if active {
            state = .subscribed
        } else if case .unavailable = state, product == nil {
            // keep the unavailable message (no product to buy anyway)
        } else {
            state = .notSubscribed
        }
    }

    func purchase() async {
        guard let product else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                }
                await refreshEntitlement()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            state = .unavailable("purchase failed: \(error.localizedDescription)")
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await loadProduct()
        await refreshEntitlement()
    }
}

// MARK: - Paywall

struct PaywallView: View {
    @ObservedObject var sub: SubscriptionManager
    let theme: Theme

    private var priceLine: String {
        if let p = sub.product { return "\(p.displayPrice)/month" }
        return "$0.99/month"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 32))
                .foregroundColor(theme.green)
            Text("ecsctl")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(theme.fg)
            VStack(alignment: .leading, spacing: 4) {
                Text("• live ECS fleet table in your menu bar")
                Text("• start / stop / restart with one click")
                Text("• FARGATE ⇄ FARGATE_SPOT switching")
                Text("• image updates, alias groups, 8 themes")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(theme.dim)

            if case .unavailable(let msg) = sub.state {
                Text("⚠️ \(msg)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.yellow)
                    .multilineTextAlignment(.center)
                Button("Retry") {
                    Task {
                        await sub.loadProduct()
                        await sub.refreshEntitlement()
                    }
                }
            } else if case .checking = sub.state {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await sub.purchase() }
                } label: {
                    if sub.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Subscribe — \(priceLine)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sub.busy || sub.product == nil)
            }

            Button("Restore Purchases") {
                Task { await sub.restore() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(theme.dim)
            .disabled(sub.busy)

            HStack(spacing: 12) {
                Link("Privacy Policy",
                     destination: URL(string: "https://github.com/oablab/ecsctl-bar/blob/main/PRIVACY.md")!)
                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.system(size: 9))
            .foregroundColor(theme.dim)

            Text("auto-renews monthly · cancel anytime in App Store settings")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(theme.dim)
            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11))
                    .foregroundColor(theme.dim)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .background(theme.bg)
    }
}
