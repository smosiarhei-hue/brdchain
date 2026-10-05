import Foundation

/// Where a host came from. Provenance matters: an unverified guess and a host
/// lifted out of the game's own logs are not the same kind of fact, and the UI
/// says so.
enum HostOrigin: String, Codable, CaseIterable {
    /// Shipped in the bundle as a starting point. May not resolve.
    case builtIn
    /// Confirmed by the user from MLBB's own network logs.
    case verified

    var label: String {
        switch self {
        case .builtIn:   return "проверяется"
        case .verified:  return "из логов"
        }
    }
}

struct Host: Identifiable, Codable, Hashable {
    let id: String
    var host: String
    var port: UInt16
    /// Region label as shown in MLBB's own first-launch server list, when known.
    var regionHint: String?
    var origin: HostOrigin
    var note: String?

    init(host: String,
         port: UInt16 = 443,
         regionHint: String? = nil,
         origin: HostOrigin = .builtIn,
         note: String? = nil) {
        self.id = "\(host):\(port)"
        self.host = host
        self.port = port
        self.regionHint = regionHint
        self.origin = origin
        self.note = note
    }
}