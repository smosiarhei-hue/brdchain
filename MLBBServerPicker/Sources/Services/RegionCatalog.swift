import Foundation

/// Seed list. Every host here is a *candidate* — the real gateway for a region
/// only becomes knowable by observing traffic on a device, so `ServerScanner`
/// treats a miss as normal and the UI lets the user add hosts by hand.
enum RegionCatalog {

    static let garenaGlobalStore = "https://apps.apple.com/app/id1202080142"

    static var all: [Region] { defaults + custom }

    static var defaults: [Region] {
        [
            Region(id: "sea-sg",
                   title: "Singapore / SEA",
                   country: "Singapore",
                   flag: "🇸🇬",
                   inGameLabel: "Singapore",
                   hosts: ["mssdk-sea.moonton.com", "sea.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "id",
                   title: "Indonesia",
                   country: "Indonesia",
                   flag: "🇮🇩",
                   inGameLabel: "Indonesia",
                   hosts: ["mssdk-id.moonton.com", "id.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "my",
                   title: "Malaysia",
                   country: "Malaysia",
                   flag: "🇲🇾",
                   inGameLabel: "Malaysia",
                   hosts: ["mssdk-my.moonton.com", "my.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "th",
                   title: "Thailand",
                   country: "Thailand",
                   flag: "🇹🇭",
                   inGameLabel: "Thailand",
                   hosts: ["mssdk-th.moonton.com", "th.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "vn",
                   title: "Vietnam",
                   country: "Vietnam",
                   flag: "🇻🇳",
                   inGameLabel: "Vietnam",
                   hosts: ["mssdk-vn.moonton.com", "vn.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "ph",
                   title: "Philippines",
                   country: "Philippines",
                   flag: "🇵🇭",
                   inGameLabel: "Philippines",
                   hosts: ["mssdk-ph.moonton.com", "ph.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "hk",
                   title: "Hong Kong / Macau",
                   country: "Hong Kong",
                   flag: "🇭🇰",
                   inGameLabel: "Hong Kong",
                   hosts: ["mssdk-hk.moonton.com", "hk.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "tw",
                   title: "Taiwan",
                   country: "Taiwan",
                   flag: "🇹🇼",
                   inGameLabel: "Taiwan",
                   hosts: ["mssdk-tw.moonton.com", "tw.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "in",
                   title: "India",
                   country: "India",
                   flag: "🇮🇳",
                   inGameLabel: "India",
                   hosts: ["mssdk-in.moonton.com", "in.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "br",
                   title: "Brazil / LATAM",
                   country: "Brazil",
                   flag: "🇧🇷",
                   inGameLabel: "Brazil",
                   hosts: ["mssdk-br.moonton.com", "br.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "tr",
                   title: "Turkey / Middle East",
                   country: "Turkey",
                   flag: "🇹🇷",
                   inGameLabel: "Turkey",
                   hosts: ["mssdk-tr.moonton.com", "tr.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "us",
                   title: "North America",
                   country: "United States",
                   flag: "🇺🇸",
                   inGameLabel: "North America",
                   hosts: ["mssdk-na.moonton.com", "na.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "ru",
                   title: "Russia / CIS",
                   country: "Russia",
                   flag: "🇷🇺",
                   inGameLabel: "Russia",
                   hosts: ["mssdk-ru.moonton.com", "ru.ml.garena.com"],
                   storeURL: garenaGlobalStore),
            Region(id: "cn",
                   title: "China (决胜巅峰)",
                   country: "China",
                   flag: "🇨🇳",
                   inGameLabel: "决胜巅峰 — отдельное приложение",
                   hosts: ["mssdk-cn.moonton.com"],
                   storeURL: "https://apps.apple.com/cn/app/id1330539243")
        ]
    }

    /// User-supplied regions, persisted in UserDefaults.
    static var custom: [Region] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "customRegions"),
                  let decoded = try? JSONDecoder().decode([Region].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: "customRegions")
        }
    }

    static func addCustom(title: String, flag: String, host: String) {
        var regions = custom
        regions.append(Region(id: "custom-\(UUID().uuidString)",
                             title: title,
                             country: "Custom",
                             flag: flag.isEmpty ? "⚙️" : flag,
                             inGameLabel: title,
                             hosts: [host],
                             storeURL: garenaGlobalStore))
        custom = regions
    }

    static func removeCustom(id: String) {
        custom = custom.filter { $0.id != id }
    }
}