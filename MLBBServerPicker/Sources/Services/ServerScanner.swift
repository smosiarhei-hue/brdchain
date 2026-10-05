import Foundation

/// One measured host.
struct HostResult: Identifiable, Hashable {
    let id: String
    let host: Host
    var latencyMS: Double?
    var error: String?

    var reachable: Bool { latencyMS != nil }
}

/// What the app can honestly conclude from a scan.
enum ScanVerdict: Equatable {
    /// At least one host confirmed from the logs answered.
    case verifiedHostReachable(HostResult)
    /// Nothing answered, and the log-import path has not been used yet.
    case noVerifiedHosts
    /// Nothing answered even though hosts were imported — genuinely unreachable.
    case nothingResponded

    var headline: String {
        switch self {
        case .verifiedHostReachable(let result):
            return "\(result.host.host) — \(String(format: "%.0f", result.latencyMS ?? 0)) ms"
        case .noVerifiedHosts:
            return "Нужен список хостов из логов"
        case .nothingResponded:
            return "Ни один хост не ответил"
        }
    }

    var detail: String {
        switch self {
        case .verifiedHostReachable:
            return "Этот хост отвечает с твоего устройства. Открой MLBB и выбери регион, соответствующий этому хосту."
        case .noVerifiedHosts:
            return "Встроенные адреса — заглушки, настоящие гейтвеи надо взять из сетевого лога MLBB. Импортируй список, и приложение измерит реальные серверы."
        case .nothingResponded:
            return "Импортированные хосты не ответили. Проверь, что список актуален для текущей версии игры, и повтори скан."
        }
    }
}

/// Probes every known host in parallel and reports what actually answered.
///
/// The design point: a host that does not resolve is *data*, not an error. The
/// built-in list is expected to mostly miss, so the scanner's job is to say
/// plainly what is alive rather than to pretend the whole catalog works.
@MainActor
final class ServerScanner: ObservableObject {

    @Published private(set) var results: [HostResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?

    var verdict: ScanVerdict {
        let reachable = results.filter(\.reachable)

        if let best = verifiedReachable.first {
            return .verifiedHostReachable(best)
        }
        return HostStore.imported.isEmpty ? .noVerifiedHosts : .nothingResponded
    }

    /// Fastest confirmed host, which is the only one the app will recommend.
    private var verifiedReachable: [HostResult] {
        results
            .filter { $0.reachable && $0.host.origin == .verified }
            .sorted { ($0.latencyMS ?? .greatestFiniteMagnitude) < ($1.latencyMS ?? .greatestFiniteMagnitude) }
    }

    func scan(concurrency: Int = 8) async {
        guard !isScanning else { return }
        isScanning = true
        scannedAt = Date()

        let hosts = HostCatalog.builtIn + HostStore.imported
        var collected: [HostResult] = []
        var index = 0

        await withTaskGroup(of: HostResult.self) { group in
            func addNext() {
                guard index < hosts.count else { return }
                let host = hosts[index]
                index += 1
                group.addTask {
                    let measurement = await PingService.measure(host: host.host, port: host.port)
                    return HostResult(id: host.id,
                                      host: host,
                                      latencyMS: measurement.latencyMS,
                                      error: measurement.error)
                }
            }

            for _ in 0..<min(concurrency, hosts.count) { addNext() }

            while let result = await group.next() {
                collected.append(result)
                addNext()
            }
        }

        results = collected
        isScanning = false
    }

    /// Reachable hosts first, fastest first. Unreachable ones keep their place
    /// at the end so the user can see what was tried.
    func sortedResults() -> [HostResult] {
        results.sorted { lhs, rhs in
            switch (lhs.reachable, rhs.reachable) {
            case (true, true):
                return (lhs.latencyMS ?? 0) < (rhs.latencyMS ?? 0)
            case (true, false):
                return true
            case (false, true):
                return false
            case (false, false):
                return lhs.host.host < rhs.host.host
            }
        }
    }

    func clear() {
        results = []
        scannedAt = nil
    }
}