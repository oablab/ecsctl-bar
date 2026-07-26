import SwiftUI
import AppKit

// MARK: - Themes (terminal-style)

struct Theme: Identifiable {
    let name: String
    let isDark: Bool
    let bg: Color
    let fg: Color
    let dim: Color
    let hoverBg: Color
    let toggleBg: Color
    let green: Color
    let red: Color
    let yellow: Color

    var id: String { name }

    static let all: [Theme] = [
        Theme(name: "GitHub Light", isDark: false,
              bg: Color(hex: 0xFFFFFF), fg: Color(hex: 0x24292E),
              dim: Color(hex: 0x959DA5), hoverBg: Color(hex: 0xF6F8FA),
              toggleBg: Color(hex: 0xE1E4E8),
              green: Color(hex: 0x2DA44E), red: Color(hex: 0xCF222E),
              yellow: Color(hex: 0x9A6700)),
        Theme(name: "GitHub Dark", isDark: true,
              bg: Color(hex: 0x0D1117), fg: Color(hex: 0xC9D1D9),
              dim: Color(hex: 0x484F58), hoverBg: Color(hex: 0x161B22),
              toggleBg: Color(hex: 0x30363D),
              green: Color(hex: 0x3FB950), red: Color(hex: 0xF85149),
              yellow: Color(hex: 0xD29922)),
        Theme(name: "Solarized Light", isDark: false,
              bg: Color(hex: 0xFDF6E3), fg: Color(hex: 0x586E75),
              dim: Color(hex: 0x93A1A1), hoverBg: Color(hex: 0xEEE8D5),
              toggleBg: Color(hex: 0xEEE8D5),
              green: Color(hex: 0x859900), red: Color(hex: 0xDC322F),
              yellow: Color(hex: 0xB58900)),
        Theme(name: "Solarized Dark", isDark: true,
              bg: Color(hex: 0x002B36), fg: Color(hex: 0x93A1A1),
              dim: Color(hex: 0x586E75), hoverBg: Color(hex: 0x073642),
              toggleBg: Color(hex: 0x073642),
              green: Color(hex: 0x859900), red: Color(hex: 0xDC322F),
              yellow: Color(hex: 0xB58900)),
        Theme(name: "Dracula", isDark: true,
              bg: Color(hex: 0x282A36), fg: Color(hex: 0xF8F8F2),
              dim: Color(hex: 0x6272A4), hoverBg: Color(hex: 0x44475A),
              toggleBg: Color(hex: 0x44475A),
              green: Color(hex: 0x50FA7B), red: Color(hex: 0xFF5555),
              yellow: Color(hex: 0xF1FA8C)),
        Theme(name: "Nord", isDark: true,
              bg: Color(hex: 0x2E3440), fg: Color(hex: 0xD8DEE9),
              dim: Color(hex: 0x4C566A), hoverBg: Color(hex: 0x3B4252),
              toggleBg: Color(hex: 0x434C5E),
              green: Color(hex: 0xA3BE8C), red: Color(hex: 0xBF616A),
              yellow: Color(hex: 0xEBCB8B)),
        Theme(name: "Blue Dolphin", isDark: true,
              bg: Color(hex: 0x06333F),      // 使用者 override：darker teal
              fg: Color(hex: 0xC5F2FF),
              dim: Color(hex: 0xA8C8D8),     // 使用者 override：palette 8
              hoverBg: Color(hex: 0x0A4653),
              toggleBg: Color(hex: 0x0E5566),
              green: Color(hex: 0xB4E88D), red: Color(hex: 0xFF8288),
              yellow: Color(hex: 0xF4D69F)),
        Theme(name: "Monokai", isDark: true,
              bg: Color(hex: 0x272822), fg: Color(hex: 0xF8F8F2),
              dim: Color(hex: 0x75715E), hoverBg: Color(hex: 0x3E3D32),
              toggleBg: Color(hex: 0x49483E),
              green: Color(hex: 0xA6E22E), red: Color(hex: 0xF92672),
              yellow: Color(hex: 0xE6DB74)),
    ]

    static func named(_ name: String) -> Theme {
        // 舊版預設名稱遷移
        if name == "Terminal Dark" { return named("GitHub Dark") }
        return all.first { $0.name == name } ?? all[0]
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Table model

struct TableRow: Identifiable {
    let id: Int
    let cells: [String]       // 依 header 欄位切開、保留 padding 空白
    var name: String { cells.first?.trimmingCharacters(in: .whitespaces) ?? "" }

    func value(_ index: Int) -> String {
        index < cells.count ? cells[index].trimmingCharacters(in: .whitespaces) : ""
    }
    var plain: String { cells.joined() }
}

struct Table {
    var headerCells: [String] = []
    var headerTitles: [String] = []
    var rows: [TableRow] = []

    func columnIndex(of title: String) -> Int? {
        headerTitles.firstIndex(of: title)
    }
}

enum TableParser {
    static let ansiPattern = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*m")

    static func stripAnsi(_ s: String) -> String {
        let ns = s as NSString
        return ansiPattern.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    // 由 header 行找出每欄起始位置，依位置切每一行
    static func parse(_ raw: String) -> Table {
        let lines = raw.components(separatedBy: "\n")
            .map(stripAnsi)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let header = lines.first else { return Table() }

        // 欄位起點：非空白字元且前一格是空白（或行首）
        var starts: [Int] = []
        let chars = Array(header)
        for i in chars.indices {
            if chars[i] != " " && (i == 0 || chars[i - 1] == " ") {
                starts.append(i)
            }
        }
        guard !starts.isEmpty else { return Table() }

        func cells(of line: String) -> [String] {
            let arr = Array(line)
            var out: [String] = []
            for (k, s) in starts.enumerated() {
                let e = k + 1 < starts.count ? starts[k + 1] : arr.count
                if s >= arr.count { out.append("") ; continue }
                out.append(String(arr[s..<min(e, arr.count)]))
            }
            return out
        }

        var table = Table()
        table.headerCells = cells(of: header)
        table.headerTitles = table.headerCells.map { $0.trimmingCharacters(in: .whitespaces) }
        table.rows = lines.dropFirst().enumerated().map { i, line in
            TableRow(id: i + 1, cells: cells(of: line))
        }
        return table
    }
}

// MARK: - Alias groups (~/.ecsctl/config.toml)

struct AliasGroup: Identifiable {
    let name: String
    let members: [String]
    var id: String { name }
}

enum GroupConfig {
    /// Config path override: ECSCTL_CONFIG env (highest) > imported CLI config
    /// mirrored in the container (sandbox) > nil (use default ~/.ecsctl).
    static var overridePath: String? {
        if let p = ProcessInfo.processInfo.environment["ECSCTL_CONFIG"], !p.isEmpty {
            return p
        }
        return ConfigShare.shared.activePath
    }

    static func load() -> [AliasGroup] {
        ConfigShare.shared.sync()
        let path = overridePath ?? NSHomeDirectory() + "/.ecsctl/config.toml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var groups: [AliasGroup] = []
        var inGroups = false
        let linePattern = try! NSRegularExpression(pattern: "^([A-Za-z0-9_-]+)\\s*=\\s*\\[(.*)\\]")
        let quoted = try! NSRegularExpression(pattern: "\"([^\"]+)\"")
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inGroups = (line == "[groups]")
                continue
            }
            guard inGroups, !line.hasPrefix("#") else { continue }
            let ns = line as NSString
            guard let m = linePattern.firstMatch(in: line,
                                                 range: NSRange(location: 0, length: ns.length))
            else { continue }
            let name = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            let bodyNS = body as NSString
            let members = quoted.matches(in: body,
                                         range: NSRange(location: 0, length: bodyNS.length))
                .map { bodyNS.substring(with: $0.range(at: 1)) }
            groups.append(AliasGroup(name: name, members: members))
        }
        return groups
    }
}

// MARK: - Store

@MainActor
final class EcsStore: ObservableObject {
    @Published var table = Table()
    @Published var loading = false
    @Published var error: String? = nil
    @Published var lastUpdated: Date? = nil
    @Published var autoRefresh = true
    @Published var actionNote: String? = nil
    @Published var busyService: String? = nil
    @Published var groups: [AliasGroup] = GroupConfig.load()

    private var timer: Timer?
    static let interval: TimeInterval = 5

    nonisolated static var binary: String {
        // MAS/sandbox: prefer an ecsctl bundled inside the app
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/ecsctl").path
        let candidates = [
            bundled,
            NSHomeDirectory() + "/.local/bin/ecsctl",
            "/usr/local/bin/ecsctl",
            "/opt/homebrew/bin/ecsctl",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[1]
    }

    enum RunResult {
        case success(String)
        case failure(String)
    }

    nonisolated static func runProcess(_ args: [String]) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        // SSO credentials (empty dict when signed out → ecsctl falls back to ~/.aws)
        for (k, v) in CredentialBridge.shared.environment() { env[k] = v }
        if let cfg = GroupConfig.overridePath { env["ECSCTL_CONFIG"] = cfg }
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(p.terminationStatus)"
                return .failure(msg)
            }
            return .success(String(data: data, encoding: .utf8) ?? "")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func start() {
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggleAuto() {
        autoRefresh.toggle()
        if autoRefresh { scheduleTimer() } else { stop() }
    }

    private func scheduleTimer() {
        guard autoRefresh else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task.detached { [weak self] in
            let result = Self.runProcess(["get", "--all"])
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let text):
                    self.table = TableParser.parse(text)
                    self.error = nil
                    self.lastUpdated = Date()
                case .failure(let e):
                    self.error = e
                }
                self.loading = false
            }
        }
    }

    /// 執行變更類指令（scale/restart/update），完成後刷新
    func mutate(_ args: [String], on name: String, note: String) {
        guard busyService == nil else { return }
        busyService = name
        actionNote = "\(note) …"
        Task.detached { [weak self] in
            let result = Self.runProcess(args)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.busyService = nil
                switch result {
                case .success:
                    self.actionNote = "✓ \(note)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if self.actionNote?.hasPrefix("✓") == true { self.actionNote = nil }
                    }
                case .failure(let msg):
                    self.actionNote = "⚠️ \(note) failed: \(msg)"
                }
                self.refresh()
            }
        }
    }

    /// 抓完整 image URI（get --all 顯示的是縮短版）
    nonisolated static func fetchImageURI(for name: String) -> String? {
        guard case .success(let yaml) = runProcess(["export", name]) else { return nil }
        for line in yaml.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("image:") {
                return t.dropFirst("image:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }
        }
        return nil
    }
}

// MARK: - Row View

struct TermRow: View {
    let row: TableRow
    let table: Table
    let theme: Theme
    let fontSize: CGFloat
    let busy: Bool
    let store: EcsStore

    @State private var hovering = false
    @State private var copied = false
    @State private var showImageEditor = false
    @State private var imageURI = ""
    @State private var imageLoading = false

    private var statusIdx: Int? { table.columnIndex(of: "STATUS") }
    private var capacityIdx: Int? { table.columnIndex(of: "CAPACITY") }
    private var imageIdx: Int? { table.columnIndex(of: "IMAGE") }

    private var status: String { statusIdx.map { row.value($0) } ?? "" }
    private var capacity: String { capacityIdx.map { row.value($0) } ?? "" }

    private func cellColor(_ index: Int) -> Color {
        if index == statusIdx {
            switch status {
            case "RUNNING": return theme.green
            case "STOPPED": return theme.red
            default:        return theme.yellow
            }
        }
        return theme.fg
    }

    private func cellText(_ index: Int) -> some View {
        Text(row.cells[index])
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundColor(cellColor(index))
            .fixedSize(horizontal: true, vertical: false)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(row.cells.indices, id: \.self) { i in
                cell(at: i)
            }
            if busy {
                ProgressView().controlSize(.mini)
            } else if copied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(theme.green)
                    .font(.system(size: fontSize))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 8)
        .background(hovering ? theme.hoverBg : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func cell(at i: Int) -> some View {
        if i == statusIdx {
            statusMenu(i)
        } else if i == capacityIdx {
            capacityMenu(i)
        } else if i == imageIdx {
            imageButton(i)
        } else {
            cellText(i)
                .onTapGesture { copyRow() }
        }
    }

    // STATUS → start | stop | restart
    private func statusMenu(_ i: Int) -> some View {
        Menu {
            Text("\(row.name) — \(status)")
            Button {
                store.mutate(["scale", row.name, "1"], on: row.name,
                             note: "start \(row.name)")
            } label: {
                Label("Start（scale 1）", systemImage: "play.fill")
            }
            .disabled(status == "RUNNING" || busy)

            Button {
                store.mutate(["scale", row.name, "0"], on: row.name,
                             note: "stop \(row.name)")
            } label: {
                Label("Stop（scale 0）", systemImage: "stop.fill")
            }
            .disabled(status == "STOPPED" || busy)

            Button {
                store.mutate(["restart", row.name], on: row.name,
                             note: "restart \(row.name)")
            } label: {
                Label("Restart（new deployment）", systemImage: "arrow.clockwise")
            }
            .disabled(status == "STOPPED" || busy)
        } label: {
            cellText(i)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("start / stop / restart")
    }

    // CAPACITY → FARGATE | FARGATE_SPOT
    private func capacityMenu(_ i: Int) -> some View {
        Menu {
            Text("\(row.name) — capacity")
            ForEach(["FARGATE", "FARGATE_SPOT"], id: \.self) { cap in
                Button {
                    store.mutate(["update", row.name, "--set", "spec.capacity=\(cap)"],
                                 on: row.name,
                                 note: "capacity \(row.name) → \(cap)")
                } label: {
                    if cap == capacity {
                        Label(cap, systemImage: "checkmark")
                    } else {
                        Text(cap)
                    }
                }
                .disabled(cap == capacity || busy)
            }
        } label: {
            cellText(i)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("切換 FARGATE / FARGATE_SPOT")
    }

    // IMAGE → 輸入完整 image URI
    private func imageButton(_ i: Int) -> some View {
        cellText(i)
            .onTapGesture {
                showImageEditor = true
                imageLoading = true
                imageURI = ""
                let name = row.name
                Task.detached {
                    let uri = EcsStore.fetchImageURI(for: name)
                    await MainActor.run {
                        imageURI = uri ?? ""
                        imageLoading = false
                    }
                }
            }
            .popover(isPresented: $showImageEditor, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Update image — \(row.name)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    HStack {
                        TextField("image URI", text: $imageURI)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 360)
                            .disabled(imageLoading)
                            .onSubmit { submitImage() }
                        if imageLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("取消") { showImageEditor = false }
                        Button("更新") { submitImage() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(imageLoading ||
                                      imageURI.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(12)
            }
            .help("點擊修改 image URI")
    }

    private func submitImage() {
        let uri = imageURI.trimmingCharacters(in: .whitespaces)
        guard !uri.isEmpty else { return }
        showImageEditor = false
        store.mutate(["update", row.name, "--set", "spec.image=\(uri)"],
                     on: row.name,
                     note: "image \(row.name) → \(uri)")
    }

    private func copyRow() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(row.plain, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { copied = false }
        }
    }
}

// MARK: - Group Row

struct GroupRow: View {
    let group: AliasGroup
    let table: Table
    let theme: Theme
    let fontSize: CGFloat
    let busy: Bool
    let store: EcsStore
    @State private var hovering = false
    @State private var confirmStop = false

    private var statusIdx: Int? { table.columnIndex(of: "STATUS") }

    private var runningCount: Int {
        guard let si = statusIdx else { return 0 }
        return group.members.filter { name in
            table.rows.first { $0.name == name }?.value(si) == "RUNNING"
        }.count
    }

    private var countColor: Color {
        if runningCount == group.members.count { return theme.green }
        if runningCount == 0 { return theme.red }
        return theme.yellow
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("@\(group.name)")
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(theme.fg)
                .frame(width: 110, alignment: .leading)

            Text("\(runningCount)/\(group.members.count) RUNNING")
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundColor(countColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 110, alignment: .leading)

            Text(group.members.joined(separator: " "))
                .font(.system(size: fontSize - 2, design: .monospaced))
                .foregroundColor(theme.dim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // hover 才出現的 start/stop（固定寬度避免重排）
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini)
                } else if confirmStop {
                    // 行內確認（modal 會讓 MenuBarExtra 視窗失焦關閉）
                    Button {
                        confirmStop = false
                        store.mutate(["scale", "@\(group.name)", "0"],
                                     on: "@\(group.name)",
                                     note: "stop @\(group.name)")
                    } label: {
                        Text("stop \(group.members.count)?")
                            .font(.system(size: fontSize - 1, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(theme.red))
                    }
                    .buttonStyle(.plain)
                    .help("再按一次確認停止全部")

                    Button {
                        confirmStop = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: fontSize - 2))
                            .foregroundColor(theme.dim)
                    }
                    .buttonStyle(.plain)
                    .help("取消")
                } else {
                    Button {
                        store.mutate(["scale", "@\(group.name)", "1"],
                                     on: "@\(group.name)",
                                     note: "start @\(group.name)")
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: fontSize))
                            .foregroundColor(theme.green)
                    }
                    .buttonStyle(.plain)
                    .help("start 全部（scale @\(group.name) 1）")
                    .opacity(hovering ? 1 : 0)

                    Button {
                        confirmStop = true
                        // 4 秒沒確認自動復原
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            confirmStop = false
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: fontSize))
                            .foregroundColor(theme.red)
                    }
                    .buttonStyle(.plain)
                    .help("stop 全部（scale @\(group.name) 0）")
                    .opacity(hovering ? 1 : 0)
                }
            }
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(hovering ? theme.hoverBg : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Content View

struct ContentView: View {
    @ObservedObject var store: EcsStore
    @ObservedObject private var sso = SSOManager.shared
    @State private var showSSO = false
    @AppStorage("themeName") private var themeName = "GitHub Dark"
    @AppStorage("fontSize") private var fontSize = 11.0
    @AppStorage("viewMode") private var viewMode = "services"   // services | groups

    private static let fontSizeRange = 9.0...16.0
    private var theme: Theme { Theme.named(themeName) }

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // 量出最寬一行的實際 pixel 寬度，讓視窗剛好裝下、不需水平捲動
    private var contentWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let all = [store.table.headerCells.joined()] + store.table.rows.map(\.plain)
        let maxLine = all
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 500
        let w = maxLine + 16 + 28
        return min(max(w, 480), 1000)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Text(viewMode == "groups" ? "$ ecsctl groups" : "$ ecsctl get --all")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(theme.fg)
                Spacer()

                // Services / Groups 切換
                HStack(spacing: 0) {
                    Button {
                        viewMode = "services"
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundColor(viewMode == "services" ? theme.fg : theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(viewMode == "services" ? theme.hoverBg : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Services view")

                    Button {
                        viewMode = "groups"
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10))
                            .foregroundColor(viewMode == "groups" ? theme.fg : theme.dim)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(viewMode == "groups" ? theme.hoverBg : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Alias groups view")
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.toggleBg))

                if store.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        store.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(theme.fg)
                    }
                    .buttonStyle(.plain)
                    .help("立即刷新")
                }

                Button {
                    store.toggleAuto()
                } label: {
                    Image(systemName: store.autoRefresh ? "pause.circle" : "play.circle")
                        .font(.system(size: 12))
                        .foregroundColor(store.autoRefresh ? theme.green : theme.dim)
                }
                .buttonStyle(.plain)
                .help(store.autoRefresh ? "暫停自動刷新（5s）" : "恢復自動刷新")

                HStack(spacing: 0) {
                    Button {
                        fontSize = max(Self.fontSizeRange.lowerBound, fontSize - 1)
                    } label: {
                        Text("A−")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(fontSize <= Self.fontSizeRange.lowerBound
                                             ? theme.dim : theme.fg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(fontSize <= Self.fontSizeRange.lowerBound)

                    Button {
                        fontSize = min(Self.fontSizeRange.upperBound, fontSize + 1)
                    } label: {
                        Text("A+")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(fontSize >= Self.fontSizeRange.upperBound
                                             ? theme.dim : theme.fg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(fontSize >= Self.fontSizeRange.upperBound)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.toggleBg))

                Button {
                    showSSO.toggle()
                } label: {
                    Image(systemName: "person.badge.key")
                        .font(.system(size: 11))
                        .foregroundColor({
                            if case .signedIn = sso.state { return theme.green }
                            if case .failed = sso.state { return theme.yellow }
                            return theme.dim
                        }())
                }
                .buttonStyle(.plain)
                .help("AWS SSO sign-in")
                .popover(isPresented: $showSSO, arrowEdge: .bottom) {
                    SSOPopover(sso: sso, theme: theme)
                }

                Menu {
                    ForEach(Theme.all) { t in
                        Button {
                            themeName = t.name
                        } label: {
                            if t.name == themeName {
                                Label(t.name, systemImage: "checkmark")
                            } else {
                                Text(t.name)
                            }
                        }
                    }
                } label: {
                    Text(theme.isDark ? "🌙" : "☀️")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.toggleBg))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("切換主題")

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                        .foregroundColor(theme.fg)
                }
                .buttonStyle(.plain)
                .help("結束")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().overlay(theme.toggleBg)

            // Body
            if let err = store.error, store.table.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(theme.yellow)
                    Text(err)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.dim)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button("重試") { store.refresh() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if viewMode != "groups", store.table.rows.isEmpty, store.lastUpdated != nil {
                // First-run: refresh succeeded but no services — guide the user
                VStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 24))
                        .foregroundColor(theme.dim)
                    Text("no services — ecsctl has no aliases configured")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.dim)
                    if !ConfigShare.shared.isLinked {
                        Button("Import ~/.ecsctl/config.toml…") {
                            if ConfigShare.shared.importViaPanel() {
                                store.groups = GroupConfig.load()
                                store.refresh()
                            }
                        }
                        Text("share your existing ecsctl CLI config with this app")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(theme.dim)
                    }
                    if case .signedIn = sso.state {} else {
                        Text("then sign in with AWS SSO (key icon above)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(theme.yellow)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if viewMode == "groups" {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.groups.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ConfigShare.shared.isLinked
                                     ? "shared config has no [groups]"
                                     : "~/.ecsctl/config.toml 沒有 [groups]")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(theme.dim)
                                Button("Import ~/.ecsctl/config.toml…") {
                                    if ConfigShare.shared.importViaPanel() {
                                        store.groups = GroupConfig.load()
                                    }
                                }
                                .font(.system(size: 11))
                            }
                            .padding()
                        } else {
                            // header row（欄寬與 GroupRow 對齊）
                            HStack(spacing: 8) {
                                Text("NAME")
                                    .frame(width: 110, alignment: .leading)
                                Text("RUNNING")
                                    .frame(minWidth: 110, alignment: .leading)
                                Text("MEMBERS")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer().frame(width: 44)
                            }
                            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.fg)
                            .padding(.vertical, 1)
                            .padding(.horizontal, 8)
                        }
                        ForEach(store.groups) { group in
                            GroupRow(group: group, table: store.table,
                                     theme: theme, fontSize: fontSize,
                                     busy: store.busyService == "@\(group.name)",
                                     store: store)
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // header row
                        HStack(spacing: 0) {
                            Text(store.table.headerCells.joined())
                                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.fg)
                                .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 8)

                        ForEach(store.table.rows) { row in
                            TermRow(row: row, table: store.table,
                                    theme: theme, fontSize: fontSize,
                                    busy: store.busyService == row.name,
                                    store: store)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Divider().overlay(theme.toggleBg)

            // Footer
            HStack {
                if let t = store.lastUpdated {
                    Text("updated \(timeFmt.string(from: t))")
                } else {
                    Text("loading…")
                }
                if let note = store.actionNote {
                    Text(note)
                        .foregroundColor(note.hasPrefix("⚠️") ? theme.yellow : theme.green)
                        .lineLimit(1)
                }
                if store.error != nil && !store.table.rows.isEmpty {
                    Text("⚠️ 上次刷新失敗")
                        .foregroundColor(theme.yellow)
                }
                Spacer()
                Text(store.autoRefresh ? "auto 5s" : "paused")
                    .foregroundColor(store.autoRefresh ? theme.green : theme.dim)
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .frame(width: contentWidth, height: 480)
        .background(theme.bg)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .onAppear {
            applyAppearance()
            store.start()
        }
        .onDisappear { store.stop() }
        .onChange(of: themeName) { _ in applyAppearance() }
    }

    private func applyAppearance() {
        NSApp.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

// MARK: - App

@main
struct EcsctlBarApp: App {
    @StateObject private var store = EcsStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Image(systemName: "shippingbox")
        }
        .menuBarExtraStyle(.window)
    }
}
