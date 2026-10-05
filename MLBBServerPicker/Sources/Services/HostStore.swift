import Foundation

/// Persists hosts the user confirmed from MLBB's own network logs.
///
/// Keyed by host:port so re-importing an overlapping log is idempotent rather
/// than producing duplicates.
struct HostStore {

    private static let key = "verifiedHosts"

    static var imported: [Host] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Host].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Merges a raw list of hostnames into the store. Existing entries keep
    /// their region hint; new ones get a nil hint until the user labels them.
    @discardableResult
    static func merge(_ raw: [String]) -> Int {
        var hosts = imported
        // Mutable: the loop inserts into it as it walks the input, so a `let`
        // here fails to compile.
        var existing = Set(hosts.map(\.id))
        var added = 0

        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Accept "host" or "host:port"; strip a scheme if one was pasted.
            var name = trimmed
            if let range = name.range(of: "://") {
                name = String(name[range.upperBound...])
            }
            if let slash = name.firstIndex(of: "/") {
                name = String(name[..<slash])
            }

            let parts = name.split(separator: ":", maxSplits: 1)
            let host = String(parts[0])
            let port = parts.count > 1 ? UInt16(parts[1]) ?? 443 : 443
            guard !host.isEmpty, host.contains(".") else { continue }

            let candidate = Host(host: host, port: port, origin: .verified)
            guard !existing.contains(candidate.id) else { continue }

            hosts.append(candidate)
            existing.insert(candidate.id)
            added += 1
        }

        imported = hosts
        return added
    }

    static func setRegionHint(_ hint: String?, for hostID: String) {
        var hosts = imported
        guard let index = hosts.firstIndex(where: { $0.id == hostID }) else { return }
        hosts[index].regionHint = hint
        imported = hosts
    }

    static func remove(id: String) {
        imported = imported.filter { $0.id != id }
    }

    static func removeAll() {
        imported = []
    }
}