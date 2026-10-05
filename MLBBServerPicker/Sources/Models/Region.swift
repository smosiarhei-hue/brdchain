import Foundation

/// A game server grouping the user can aim at. `hosts` are candidate
/// gateways — they get calibrated on-device, see `ServerScanner`.
struct Region: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var country: String
    var flag: String
    /// Where the user picks this region inside MLBB's first-launch screen.
    var inGameLabel: String
    var hosts: [String]
    var storeURL: String

    var displayName: String { "\(flag)  \(title)" }
}

/// Live measurement for one host:port pair.
struct Probe: Identifiable, Hashable {
    let id = UUID()
    let region: Region
    let host: String
    let port: UInt16
    var latencyMS: Double?
    var error: String?

    var reachable: Bool { latencyMS != nil }
}