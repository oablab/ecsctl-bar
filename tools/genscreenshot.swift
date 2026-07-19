// Generate marketing screenshots for ecsctl Bar (like deepsrt-x-bar's).
// Uses live `ecsctl get --all` output + ~/.ecsctl/config.toml groups.
// Usage: swift genscreenshot.swift <out-dir>
import SwiftUI
import AppKit

// MARK: data

func runEcsctl(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/ecsctl")
    p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    try! p.run()
    let d = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: d, encoding: .utf8) ?? ""
}

let ansi = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*m")
func strip(_ s: String) -> String {
    ansi.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
}

struct Row { let cells: [String]; var name: String { cells[0].trimmingCharacters(in: .whitespaces) } }

func parseTable(_ raw: String) -> (header: [String], rows: [Row]) {
    let lines = raw.components(separatedBy: "\n").map(strip).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    guard let header = lines.first else { return ([], []) }
    var starts: [Int] = []
    let chars = Array(header)
    for i in chars.indices where chars[i] != " " && (i == 0 || chars[i - 1] == " ") { starts.append(i) }
    func cells(_ line: String) -> [String] {
        let arr = Array(line)
        return starts.enumerated().map { k, s in
            let e = k + 1 < starts.count ? starts[k + 1] : arr.count
            return s < arr.count ? String(arr[s..<min(e, arr.count)]) : ""
        }
    }
    return (cells(header), lines.dropFirst().map { Row(cells: cells($0)) })
}

func parseGroups() -> [(String, [String])] {
    guard let text = try? String(contentsOfFile: NSHomeDirectory() + "/.ecsctl/config.toml", encoding: .utf8) else { return [] }
    var out: [(String, [String])] = []
    var inGroups = false
    let lp = try! NSRegularExpression(pattern: "^([A-Za-z0-9_-]+)\\s*=\\s*\\[(.*)\\]")
    let q = try! NSRegularExpression(pattern: "\"([^\"]+)\"")
    for raw in text.components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") { inGroups = (line == "[groups]"); continue }
        guard inGroups, !line.hasPrefix("#") else { continue }
        let ns = line as NSString
        guard let m = lp.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
        let body = ns.substring(with: m.range(at: 2)) as NSString
        let members = q.matches(in: body as String, range: NSRange(location: 0, length: body.length)).map { body.substring(with: $0.range(at: 1)) }
        out.append((ns.substring(with: m.range(at: 1)), members))
    }
    return out
}

// MARK: palettes

struct Palette {
    let name: String
    let bg, fg, dim, hover, toggle, green, red, yellow: Color
    let deskTop, deskBottom: Color
    let lightText: Bool
}

let githubdark = Palette(
    name: "GitHub Dark",
    bg: Color(red: 0x0D/255.0, green: 0x11/255.0, blue: 0x17/255.0),
    fg: Color(red: 0xC9/255.0, green: 0xD1/255.0, blue: 0xD9/255.0),
    dim: Color(red: 0x48/255.0, green: 0x4F/255.0, blue: 0x58/255.0),
    hover: Color(red: 0x16/255.0, green: 0x1B/255.0, blue: 0x22/255.0),
    toggle: Color(red: 0x30/255.0, green: 0x36/255.0, blue: 0x3D/255.0),
    green: Color(red: 0x3F/255.0, green: 0xB9/255.0, blue: 0x50/255.0),
    red: Color(red: 0xF8/255.0, green: 0x51/255.0, blue: 0x49/255.0),
    yellow: Color(red: 0xD2/255.0, green: 0x99/255.0, blue: 0x22/255.0),
    deskTop: Color(red: 0x2B/255.0, green: 0x33/255.0, blue: 0x42/255.0),
    deskBottom: Color(red: 0x05/255.0, green: 0x07/255.0, blue: 0x0A/255.0),
    lightText: true)

let bluedolphin = Palette(
    name: "Blue Dolphin",
    bg: Color(red: 0x06/255.0, green: 0x33/255.0, blue: 0x3F/255.0),
    fg: Color(red: 0xC5/255.0, green: 0xF2/255.0, blue: 0xFF/255.0),
    dim: Color(red: 0xA8/255.0, green: 0xC8/255.0, blue: 0xD8/255.0),
    hover: Color(red: 0x0A/255.0, green: 0x46/255.0, blue: 0x53/255.0),
    toggle: Color(red: 0x0E/255.0, green: 0x55/255.0, blue: 0x66/255.0),
    green: Color(red: 0xB4/255.0, green: 0xE8/255.0, blue: 0x8D/255.0),
    red: Color(red: 0xFF/255.0, green: 0x82/255.0, blue: 0x88/255.0),
    yellow: Color(red: 0xF4/255.0, green: 0xD6/255.0, blue: 0x9F/255.0),
    deskTop: Color(red: 0x0E/255.0, green: 0x55/255.0, blue: 0x66/255.0),
    deskBottom: Color(red: 0x03/255.0, green: 0x1A/255.0, blue: 0x21/255.0),
    lightText: true)

// MARK: window chrome

struct Chrome<Content: View>: View {
    let p: Palette
    let title: String
    let footerLeft: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(p.fg)
                Spacer()
                HStack(spacing: 0) {
                    Image(systemName: "list.bullet").font(.system(size: 10)).foregroundColor(p.fg)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(p.hover))
                    Image(systemName: "square.grid.2x2").font(.system(size: 10)).foregroundColor(p.dim)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 6).fill(p.toggle))
                Image(systemName: "arrow.clockwise").font(.system(size: 11)).foregroundColor(p.fg)
                Image(systemName: "pause.circle").font(.system(size: 12)).foregroundColor(p.green)
                Text("A− A+").font(.system(size: 9, design: .monospaced)).foregroundColor(p.fg)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.toggle))
                Text("🌙").font(.system(size: 10))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(p.toggle))
                Image(systemName: "power").font(.system(size: 11)).foregroundColor(p.fg)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider().overlay(p.toggle)
            content
            Divider().overlay(p.toggle)
            HStack {
                Text(footerLeft)
                Spacer()
                Text("auto 5s").foregroundColor(p.green)
            }
            .font(.system(size: 9, design: .monospaced)).foregroundColor(p.dim)
            .padding(.horizontal, 12).padding(.vertical, 5)
        }
        .background(p.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }
}

// MARK: services view

struct ServicesShot: View {
    let header: [String]
    let rows: [Row]
    let p: Palette
    let highlightRow: Int
    let fontSize: CGFloat = 11

    func statusColor(_ s: String) -> Color {
        switch s.trimmingCharacters(in: .whitespaces) {
        case "RUNNING": return p.green
        case "STOPPED": return p.red
        default: return p.yellow
        }
    }

    var body: some View {
        Chrome(p: p, title: "$ ecsctl get --all",
               footerLeft: "updated 21:33:05  ✓ restart b7") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text(header.joined())
                        .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                        .foregroundColor(p.fg)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 1).padding(.horizontal, 8)
                ForEach(rows.indices, id: \.self) { i in
                    let r = rows[i]
                    HStack(spacing: 0) {
                        ForEach(r.cells.indices, id: \.self) { c in
                            Text(r.cells[c])
                                .font(.system(size: fontSize, design: .monospaced))
                                .foregroundColor(c == 1 ? statusColor(r.cells[c]) : p.fg)
                        }
                        if i == highlightRow {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: fontSize))
                                .foregroundColor(p.fg.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 1).padding(.horizontal, 8)
                    .background(i == highlightRow ? p.hover : .clear)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: groups view

struct GroupsShot: View {
    let groups: [(String, [String])]
    let running: [String: Bool]
    let p: Palette
    let hoverIndex: Int
    let fontSize: CGFloat = 11

    var body: some View {
        Chrome(p: p, title: "$ ecsctl groups",
               footerLeft: "updated 21:33:05") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("NAME").frame(width: 110, alignment: .leading)
                    Text("RUNNING").frame(minWidth: 110, alignment: .leading)
                    Text("MEMBERS").frame(maxWidth: .infinity, alignment: .leading)
                    Spacer().frame(width: 44)
                }
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(p.fg)
                .padding(.vertical, 1).padding(.horizontal, 8)
                ForEach(groups.indices, id: \.self) { i in
                    let (name, members) = groups[i]
                    let run = members.filter { running[$0] ?? false }.count
                    HStack(spacing: 8) {
                        Text("@\(name)")
                            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(p.fg)
                            .frame(width: 110, alignment: .leading)
                        Text("\(run)/\(members.count) RUNNING")
                            .font(.system(size: fontSize, design: .monospaced))
                            .foregroundColor(run == members.count ? p.green : (run == 0 ? p.red : p.yellow))
                            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 110, alignment: .leading)
                        Text(members.joined(separator: " "))
                            .font(.system(size: fontSize - 2, design: .monospaced))
                            .foregroundColor(p.dim)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            if i == hoverIndex {
                                Image(systemName: "play.fill").font(.system(size: fontSize)).foregroundColor(p.green)
                                Image(systemName: "stop.fill").font(.system(size: fontSize)).foregroundColor(p.red)
                            }
                        }
                        .frame(minWidth: 44, alignment: .trailing)
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(i == hoverIndex ? p.hover : .clear)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: composed shot

struct Shot<W: View>: View {
    let p: Palette
    let headline: String
    let sub: String
    let window: W

    var body: some View {
        ZStack {
            LinearGradient(colors: [p.deskTop, p.deskBottom], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("📦").font(.system(size: 64))
                    Text(headline)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sub)
                        .font(.system(size: 19))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 400)
                window
            }
            .padding(.horizontal, 70)
        }
        .frame(width: 1440, height: 900)
    }
}

// MARK: render

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "screenshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let (header, allRows) = parseTable(runEcsctl(["get", "--all"]))
let rows = Array(allRows.prefix(18))
let running = Dictionary(uniqueKeysWithValues: allRows.map {
    ($0.name, $0.cells.count > 1 && $0.cells[1].trimmingCharacters(in: .whitespaces) == "RUNNING")
})
let groups = parseGroups()

@MainActor
func render(_ view: some View, to path: String) {
    let r = ImageRenderer(content: view)
    r.scale = 2.0
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("render failed \(path)"); return
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

await MainActor.run {
    render(Shot(p: githubdark,
                headline: "Your ECS fleet,\nright in the menu bar",
                sub: "Live ecsctl get --all table\nAuto-refresh every 5 s\nClick STATUS to start / stop / restart\nClick CAPACITY to switch FARGATE / SPOT\nClick IMAGE to update the image URI in place",
                window: ServicesShot(header: header, rows: rows, p: githubdark, highlightRow: 7)),
           to: "\(outDir)/shot1-services.png")
    render(Shot(p: bluedolphin,
                headline: "Alias groups,\nbulk operations",
                sub: "Reads [groups] from ~/.ecsctl/config.toml\nLive aggregate RUNNING status\nHover for ▶ start / ■ stop\nBulk stop requires confirmation",
                window: GroupsShot(groups: groups, running: running, p: bluedolphin, hoverIndex: 1)),
           to: "\(outDir)/shot2-groups.png")
}
