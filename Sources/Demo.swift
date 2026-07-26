import Foundation

/// Canned fleet for App Review / trying the app without AWS.
/// Renders output byte-compatible with `ecsctl get --all` (ANSI colors
/// included) so the whole UI pipeline works unchanged, and mutations
/// (scale/restart/update) update the model so the controls demonstrably work.
enum DemoFleet {
    struct Service {
        var name: String
        var status: String   // RUNNING / STOPPED / PENDING
        var cpu: String
        var mem: String
        var capacity: String // FARGATE / FARGATE_SPOT
        var image: String
        var tasks: String
    }

    private static let lock = NSLock()
    private static var services: [Service] = [
        .init(name: "api", status: "RUNNING", cpu: "1024", mem: "2048",
              capacity: "FARGATE", image: "demo/api:v1.4.2", tasks: "2"),
        .init(name: "worker", status: "RUNNING", cpu: "2048", mem: "4096",
              capacity: "FARGATE_SPOT", image: "demo/worker:v1.4.2", tasks: "4"),
        .init(name: "scheduler", status: "RUNNING", cpu: "512", mem: "1024",
              capacity: "FARGATE_SPOT", image: "demo/scheduler:v0.9.1", tasks: "1"),
        .init(name: "webhook", status: "STOPPED", cpu: "512", mem: "1024",
              capacity: "FARGATE_SPOT", image: "demo/webhook:v2.0.0", tasks: "0"),
        .init(name: "batch", status: "STOPPED", cpu: "4096", mem: "8192",
              capacity: "FARGATE", image: "demo/batch:v3.1.0", tasks: "0"),
    ]

    static let groups: [AliasGroup] = [
        AliasGroup(name: "core", members: ["api", "worker", "scheduler"]),
        AliasGroup(name: "jobs", members: ["webhook", "batch"]),
    ]

    private static func color(_ status: String) -> String {
        switch status {
        case "RUNNING": return "\u{1B}[32m"
        case "STOPPED": return "\u{1B}[31m"
        default: return "\u{1B}[33m"
        }
    }

    /// Render in the `ecsctl get --all` table format.
    static func render() -> String {
        lock.lock(); defer { lock.unlock() }
        func pad(_ s: String, _ w: Int) -> String {
            s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
        }
        var out = pad("NAME", 16) + pad("STATUS", 17) + pad("CPU", 7)
            + pad("MEM", 7) + pad("CAPACITY", 16) + pad("IMAGE", 31) + "TASKS\n"
        for s in services {
            out += pad(s.name, 16)
                + color(s.status) + pad(s.status, 16) + "\u{1B}[0m "
                + pad(s.cpu, 7) + pad(s.mem, 7) + pad(s.capacity, 16)
                + pad(s.image, 31) + s.tasks + "\n"
        }
        return out
    }

    /// Apply a mutation the way ecsctl would (scale/restart/update).
    static func apply(_ args: [String]) {
        lock.lock(); defer { lock.unlock() }
        guard args.count >= 2 else { return }
        let cmd = args[0], target = args[1]
        let names: [String] = target.hasPrefix("@")
            ? (groups.first { $0.name == target.dropFirst() }?.members ?? [])
            : [target]
        for name in names {
            guard let i = services.firstIndex(where: { $0.name == name }) else { continue }
            switch cmd {
            case "scale":
                let n = args.count > 2 ? args[2] : "1"
                services[i].status = n == "0" ? "STOPPED" : "RUNNING"
                services[i].tasks = n
            case "restart":
                services[i].status = "RUNNING"
                if services[i].tasks == "0" { services[i].tasks = "1" }
            case "update":
                for a in args where a.hasPrefix("spec.capacity=") {
                    services[i].capacity = String(a.dropFirst("spec.capacity=".count))
                }
                for a in args where a.hasPrefix("spec.image=") {
                    services[i].image = String(a.dropFirst("spec.image=".count))
                }
            default:
                break
            }
        }
    }

    static func imageURI(for name: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return services.first { $0.name == name }
            .map { "123456789012.dkr.ecr.us-east-1.amazonaws.com/\($0.image)" }
    }
}
