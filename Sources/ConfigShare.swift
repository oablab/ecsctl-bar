import AppKit

/// Shares the user's ecsctl CLI config (`~/.ecsctl/config.toml`) with the app
/// under App Sandbox.
///
/// Mechanism: one-time NSOpenPanel selection (the user gesture IS the sandbox
/// grant) → security-scoped bookmark persisted in UserDefaults → on every
/// sync, read the real file and mirror it into the app container. The bundled
/// ecsctl subprocess then reads the container copy via ECSCTL_CONFIG — no
/// reliance on sandbox-extension inheritance in child processes.
///
/// Safe because the pipeline is read-only: the app never writes config
/// (it only runs get/scale/restart/update/export). One-way CLI → app sync.
final class ConfigShare: @unchecked Sendable {
    static let shared = ConfigShare()
    private let bookmarkKey = "cliConfigBookmark"
    private let lock = NSLock()

    /// Container-local mirror handed to ecsctl via ECSCTL_CONFIG.
    let containerCopyPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("ecsctl-bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.toml").path
    }()

    var isLinked: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
            || FileManager.default.fileExists(atPath: containerCopyPath)
    }

    /// Path GroupConfig + the subprocess should use, or nil to fall back to
    /// the default ~/.ecsctl/config.toml (non-sandboxed builds).
    var activePath: String? {
        guard isLinked else { return nil }
        return containerCopyPath
    }

    /// Show the open panel pre-navigated to ~/.ecsctl. Returns true on grant.
    @MainActor
    func importViaPanel() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Share ecsctl CLI config"
        panel.message = "Select your ecsctl config.toml — the app will stay in sync with it."
        panel.prompt = "Use This Config"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/.ecsctl")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        // Copy right now, under the open panel's grant — succeeds even if
        // bookmarking fails, so the import is never a silent no-op.
        let copied = (try? Data(contentsOf: url))
            .flatMap { try? $0.write(to: URL(fileURLWithPath: containerCopyPath),
                                     options: .atomic) } != nil
        // Bookmark enables live re-sync on future launches (needs the
        // files.bookmarks.app-scope entitlement).
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } else {
            NSLog("ConfigShare: bookmark creation failed — one-time copy only")
        }
        return copied || sync()
    }

    func unlink() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        try? FileManager.default.removeItem(atPath: containerCopyPath)
    }

    /// Mirror the granted file into the container (mtime-checked).
    /// Cheap no-op when unchanged. Returns true if the copy is usable.
    @discardableResult
    func sync() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return false }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        guard url.startAccessingSecurityScopedResource() else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        let fm = FileManager.default
        let srcMtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        let dstMtime = (try? fm.attributesOfItem(atPath: containerCopyPath)[.modificationDate]) as? Date
        if let s = srcMtime, let d = dstMtime, s <= d {
            return true // up to date
        }
        guard let content = try? Data(contentsOf: url) else {
            return fm.fileExists(atPath: containerCopyPath) // keep last good copy
        }
        try? content.write(to: URL(fileURLWithPath: containerCopyPath), options: .atomic)
        return true
    }
}
