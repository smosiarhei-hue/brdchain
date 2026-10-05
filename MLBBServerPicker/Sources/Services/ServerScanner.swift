import Foundation

/// Fans out one probe per host, in parallel, and keeps the best result per
/// region. Regions whose hosts all fail stay in the list marked unreachable
/// rather than being dropped — a silent gap reads like a bug.
@MainActor
final class ServerScanner: ObservableObject {

    @Published private(set) var probes: [Probe] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedAt: Date?

    /// Per-region best latency, ascending. Unreachable regions excluded.
    private(set) var ranking: [(region: Region, latencyMS: Double)] = []

    func scan(port: UInt16 = 443, concurrency: Int = 8) async {
        guard !isScanning else { return }
        isScanning = true
        scannedAt = Date()

        let work = RegionCatalog.all.flatMap { region in
            region.hosts.map { (region, $0) }
        }

        var results: [Probe] = []
        var index = 0

        await withTaskGroup(of: Probe.self) { group in
            func addNext() {
                guard index < work.count else { return }
                let (region, host) = work[index]
                index += 1
                group.addTask {
                    let measurement = await PingService.measure(host: host, port: port)
                    return Probe(region: region,
                                 host: host,
                                 port: port,
                                 latencyMS: measurement.latencyMS,
                                 error: measurement.error)
                }
            }

            for _ in 0..<min(concurrency, work.count) { addNext() }

            while let probe = await group.next() {
                results.append(probe)
                addNext()
            }
        }

        probes = results
        ranking = bestPerRegion(from: results)
        isScanning = false
    }

    private func bestPerRegion(from results: [Probe]) -> [(region: Region, latencyMS: Double)] {
        var best: [String: (Region, Double)] = [:]

        for probe in results {
            guard let latency = probe.latencyMS else { continue }
            let current = best[probe.region.id]
            if current == nil || latency < current!.1 {
                best[probe.region.id] = (probe.region, latency)
            }
        }

        return best.values
            .sorted { $0.1 < $1.1 }
            .map { (region: $0.0, latencyMS: $0.1) }
    }

    func bestProbe(for regionID: String) -> Probe? {
        probes
            .filter { $0.region.id == regionID && $0.reachable }
            .min { ($0.latencyMS ?? .greatestFiniteMagnitude) < ($1.latencyMS ?? .greatestFiniteMagnitude) }
    }

    func clear() {
        probes = []
        ranking = []
        scannedAt = nil
    }
}