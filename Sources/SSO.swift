import SwiftUI
import Security

// MARK: - Keychain

/// Minimal Keychain wrapper for persisting the SSO session across launches.
enum Keychain {
    private static let service = "dev.pahud.ecsctl.sso"

    static func save(_ data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Session model

/// Everything we persist between launches (Keychain, single blob).
struct SSOSession: Codable {
    var startUrl: String
    var ssoRegion: String
    // OIDC client registration (valid ~90 days)
    var clientId: String
    var clientSecret: String
    var clientExpiresAt: Date
    // Access token from device flow (valid ~8h)
    var accessToken: String?
    var tokenExpiresAt: Date?
    // Selected role
    var accountId: String?
    var roleName: String?
    // Cached role credentials (valid ~1h)
    var accessKeyId: String?
    var secretAccessKey: String?
    var sessionToken: String?
    var credentialsExpireAt: Date?

    var tokenValid: Bool {
        guard let t = tokenExpiresAt, accessToken != nil else { return false }
        return t > Date().addingTimeInterval(60)
    }

    var credentialsValid: Bool {
        guard let t = credentialsExpireAt, accessKeyId != nil else { return false }
        return t > Date().addingTimeInterval(300)
    }
}

// MARK: - Credential bridge (thread-safe env vars for the ecsctl subprocess)

/// `EcsStore.runProcess` is nonisolated/sync; this hands it the current
/// credentials without touching the MainActor.
final class CredentialBridge: @unchecked Sendable {
    static let shared = CredentialBridge()
    private let lock = NSLock()
    private var env: [String: String] = [:]

    func set(accessKeyId: String, secretAccessKey: String, sessionToken: String, region: String) {
        lock.lock(); defer { lock.unlock() }
        env = [
            "AWS_ACCESS_KEY_ID": accessKeyId,
            "AWS_SECRET_ACCESS_KEY": secretAccessKey,
            "AWS_SESSION_TOKEN": sessionToken,
            "AWS_REGION": region,
            "AWS_DEFAULT_REGION": region,
        ]
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        env = [:]
    }

    /// Env vars to merge into the subprocess environment. Empty when signed out
    /// (ecsctl then falls back to ~/.aws as before).
    func environment() -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        return env
    }
}

// MARK: - SSO Manager

struct SSOAccount: Identifiable, Hashable {
    let accountId: String
    let accountName: String
    var id: String { accountId }
}

@MainActor
final class SSOManager: ObservableObject {
    static let shared = SSOManager()

    enum State: Equatable {
        case signedOut
        case authorizing(userCode: String)   // waiting for browser approval
        case selectingRole                   // token OK, picking account/role
        case signedIn(accountId: String, roleName: String)
        case failed(String)
    }

    @Published var state: State = .signedOut
    @Published var accounts: [SSOAccount] = []
    @Published var roles: [String] = []
    @Published var selectedAccount: String = ""
    @Published var selectedRole: String = ""
    @Published var busy = false

    /// Region the fleet lives in (passed to ecsctl as AWS_REGION).
    @AppStorage("fleetRegion") var fleetRegion = "us-east-1"
    @AppStorage("ssoStartUrl") var startUrl = ""
    @AppStorage("ssoRegion") var ssoRegion = "us-east-1"

    private var session: SSOSession?
    private var pollTask: Task<Void, Never>?
    private var renewTimer: Timer?
    private static let keychainAccount = "session"

    private init() {
        restore()
        // Renew role credentials before they expire (checked every minute).
        renewTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await SSOManager.shared.ensureFresh() }
        }
    }

    // MARK: Persistence

    private func persist() {
        guard let s = session, let data = try? JSONEncoder().encode(s) else { return }
        Keychain.save(data, account: Self.keychainAccount)
    }

    private func restore() {
        guard let data = Keychain.load(account: Self.keychainAccount),
              let s = try? JSONDecoder().decode(SSOSession.self, from: data) else { return }
        session = s
        if s.credentialsValid, let ak = s.accessKeyId, let sk = s.secretAccessKey,
           let st = s.sessionToken, let acct = s.accountId, let role = s.roleName {
            CredentialBridge.shared.set(accessKeyId: ak, secretAccessKey: sk,
                                        sessionToken: st, region: fleetRegion)
            state = .signedIn(accountId: acct, roleName: role)
        } else if s.tokenValid, let acct = s.accountId, let role = s.roleName {
            // Token still good — refresh credentials silently.
            state = .signedIn(accountId: acct, roleName: role)
            Task { await ensureFresh(force: true) }
        } else if s.tokenValid {
            state = .selectingRole
            Task { await loadAccounts() }
        }
    }

    // MARK: HTTP helpers

    private var oidcBase: String { "https://oidc.\(ssoRegion).amazonaws.com" }
    private var portalBase: String { "https://portal.sso.\(ssoRegion).amazonaws.com" }

    private func postJSON(_ url: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let code = json["error"] as? String ?? "http \(http.statusCode)"
            throw SSOError(code: code,
                           message: json["error_description"] as? String ?? code)
        }
        return json
    }

    private func getJSON(_ url: String, token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(token, forHTTPHeaderField: "x-amz-sso_bearer_token")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SSOError(code: "http \(http.statusCode)",
                           message: (json["message"] as? String) ?? "portal request failed")
        }
        return json
    }

    struct SSOError: Error { let code: String; let message: String }

    // MARK: Device flow

    func signIn() {
        let start = startUrl.trimmingCharacters(in: .whitespaces)
        guard start.hasPrefix("https://") else {
            state = .failed("start URL must be https://…awsapps.com/start")
            return
        }
        busy = true
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.runDeviceFlow(start: start)
        }
    }

    private func runDeviceFlow(start: String) async {
        do {
            // 1. RegisterClient (reuse a previous registration if still valid)
            var s = session
            if s == nil || !(s!.clientExpiresAt > Date() && s!.startUrl == start
                             && s!.ssoRegion == ssoRegion) {
                let reg = try await postJSON("\(oidcBase)/client/register", body: [
                    "clientName": "ecsctl-bar",
                    "clientType": "public",
                ])
                s = SSOSession(
                    startUrl: start, ssoRegion: ssoRegion,
                    clientId: reg["clientId"] as? String ?? "",
                    clientSecret: reg["clientSecret"] as? String ?? "",
                    clientExpiresAt: Date(timeIntervalSince1970:
                        (reg["clientSecretExpiresAt"] as? Double) ?? 0))
            }
            guard var sess = s else { return }

            // 2. StartDeviceAuthorization
            let auth = try await postJSON("\(oidcBase)/device_authorization", body: [
                "clientId": sess.clientId,
                "clientSecret": sess.clientSecret,
                "startUrl": start,
            ])
            guard let deviceCode = auth["deviceCode"] as? String,
                  let userCode = auth["userCode"] as? String else {
                throw SSOError(code: "bad_response", message: "device authorization failed")
            }
            let verifyUrl = (auth["verificationUriComplete"] as? String)
                ?? (auth["verificationUri"] as? String) ?? ""
            var interval = (auth["interval"] as? Double) ?? 5
            let deadline = Date().addingTimeInterval((auth["expiresIn"] as? Double) ?? 600)

            state = .authorizing(userCode: userCode)
            busy = false
            if let u = URL(string: verifyUrl) { NSWorkspace.shared.open(u) }

            // 3. Poll CreateToken
            while Date() < deadline, !Task.isCancelled {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                do {
                    let tok = try await postJSON("\(oidcBase)/token", body: [
                        "clientId": sess.clientId,
                        "clientSecret": sess.clientSecret,
                        "grantType": "urn:ietf:params:oauth:grant-type:device_code",
                        "deviceCode": deviceCode,
                    ])
                    sess.accessToken = tok["accessToken"] as? String
                    sess.tokenExpiresAt = Date()
                        .addingTimeInterval((tok["expiresIn"] as? Double) ?? 28800)
                    session = sess
                    persist()
                    state = .selectingRole
                    await loadAccounts()
                    return
                } catch let e as SSOError where e.code == "authorization_pending" {
                    continue
                } catch let e as SSOError where e.code == "slow_down" {
                    interval += 5
                }
            }
            if !Task.isCancelled {
                state = .failed("authorization timed out — try again")
            }
        } catch let e as SSOError {
            state = .failed(e.message)
            busy = false
        } catch {
            state = .failed(error.localizedDescription)
            busy = false
        }
    }

    func cancelSignIn() {
        pollTask?.cancel()
        pollTask = nil
        busy = false
        if case .authorizing = state { state = .signedOut }
    }

    func signOut() {
        pollTask?.cancel()
        session = nil
        Keychain.delete(account: Self.keychainAccount)
        CredentialBridge.shared.clear()
        accounts = []
        roles = []
        state = .signedOut
    }

    // MARK: Account / role selection

    func loadAccounts() async {
        guard let token = session?.accessToken else { return }
        busy = true
        defer { busy = false }
        do {
            let json = try await getJSON(
                "\(portalBase)/assignment/accounts?max_result=100", token: token)
            let list = (json["accountList"] as? [[String: Any]]) ?? []
            accounts = list.compactMap { a in
                guard let id = a["accountId"] as? String else { return nil }
                return SSOAccount(accountId: id,
                                  accountName: a["accountName"] as? String ?? id)
            }
            if let first = accounts.first {
                selectedAccount = session?.accountId ?? first.accountId
                await loadRoles()
            }
        } catch {
            state = .failed("list accounts: \((error as? SSOError)?.message ?? error.localizedDescription)")
        }
    }

    func loadRoles() async {
        guard let token = session?.accessToken, !selectedAccount.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let json = try await getJSON(
                "\(portalBase)/assignment/roles?account_id=\(selectedAccount)&max_result=100",
                token: token)
            roles = ((json["roleList"] as? [[String: Any]]) ?? [])
                .compactMap { $0["roleName"] as? String }
            selectedRole = (session?.roleName.flatMap { roles.contains($0) ? $0 : nil })
                ?? roles.first ?? ""
        } catch {
            state = .failed("list roles: \((error as? SSOError)?.message ?? error.localizedDescription)")
        }
    }

    func useSelectedRole() async {
        guard var s = session, !selectedAccount.isEmpty, !selectedRole.isEmpty else { return }
        s.accountId = selectedAccount
        s.roleName = selectedRole
        session = s
        persist()
        await fetchRoleCredentials()
    }

    private func fetchRoleCredentials() async {
        guard var s = session, let token = s.accessToken,
              let acct = s.accountId, let role = s.roleName else { return }
        busy = true
        defer { busy = false }
        do {
            let json = try await getJSON(
                "\(portalBase)/federation/credentials?account_id=\(acct)&role_name=\(role)",
                token: token)
            guard let creds = json["roleCredentials"] as? [String: Any],
                  let ak = creds["accessKeyId"] as? String,
                  let sk = creds["secretAccessKey"] as? String,
                  let st = creds["sessionToken"] as? String else {
                throw SSOError(code: "bad_response", message: "no credentials in response")
            }
            let expMs = (creds["expiration"] as? Double) ?? 0
            s.accessKeyId = ak
            s.secretAccessKey = sk
            s.sessionToken = st
            s.credentialsExpireAt = Date(timeIntervalSince1970: expMs / 1000)
            session = s
            persist()
            CredentialBridge.shared.set(accessKeyId: ak, secretAccessKey: sk,
                                        sessionToken: st, region: fleetRegion)
            state = .signedIn(accountId: acct, roleName: role)
        } catch {
            state = .failed("get credentials: \((error as? SSOError)?.message ?? error.localizedDescription)")
        }
    }

    /// Called by a timer: refresh role credentials while the token is valid;
    /// drop to signedOut when everything expired.
    func ensureFresh(force: Bool = false) async {
        guard let s = session, case .signedIn = state else { return }
        if s.credentialsValid && !force { return }
        if s.tokenValid {
            await fetchRoleCredentials()
        } else {
            CredentialBridge.shared.clear()
            state = .signedOut
        }
    }
}

// MARK: - UI

struct SSOPopover: View {
    @ObservedObject var sso: SSOManager
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AWS SSO")
                .font(.system(size: 12, weight: .bold, design: .monospaced))

            switch sso.state {
            case .signedOut, .failed:
                if case .failed(let msg) = sso.state {
                    Text("⚠️ \(msg)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.yellow)
                        .lineLimit(3)
                }
                TextField("https://xxx.awsapps.com/start", text: $sso.startUrl)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                HStack {
                    Text("SSO region")
                    TextField("us-east-1", text: $sso.ssoRegion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Text("fleet")
                    TextField("us-east-1", text: $sso.fleetRegion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                }
                .font(.system(size: 10, design: .monospaced))
                Button {
                    sso.signIn()
                } label: {
                    if sso.busy { ProgressView().controlSize(.small) }
                    else { Text("Sign in with AWS") }
                }
                .disabled(sso.busy || sso.startUrl.isEmpty)

            case .authorizing(let userCode):
                Text("Confirm this code in your browser:")
                    .font(.system(size: 11))
                Text(userCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    ProgressView().controlSize(.small)
                    Text("waiting for approval…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Button("Cancel") { sso.cancelSignIn() }

            case .selectingRole:
                Picker("Account", selection: $sso.selectedAccount) {
                    ForEach(sso.accounts) { a in
                        Text("\(a.accountName) (\(a.accountId))").tag(a.accountId)
                    }
                }
                .onChange(of: sso.selectedAccount) { _ in
                    Task { await sso.loadRoles() }
                }
                Picker("Role", selection: $sso.selectedRole) {
                    ForEach(sso.roles, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Button {
                        Task { await sso.useSelectedRole() }
                    } label: {
                        if sso.busy { ProgressView().controlSize(.small) }
                        else { Text("Use this role") }
                    }
                    .disabled(sso.busy || sso.selectedRole.isEmpty)
                    Button("Sign out") { sso.signOut() }
                }

            case .signedIn(let accountId, let roleName):
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("\(roleName) @ \(accountId)")
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                Text("credentials injected into ecsctl env")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                HStack {
                    Button("Switch role") {
                        sso.state = .selectingRole
                        Task { await sso.loadAccounts() }
                    }
                    Button("Sign out") { sso.signOut() }
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
