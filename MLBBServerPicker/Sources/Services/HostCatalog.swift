import Foundation

/// Moonton service infrastructure. These are used for update checks and
/// account flows, and are commonly reachable even when a game gateway is
/// region-locked — so they double as a liveness check for the app itself.
///
/// These are probes, not facts. Most game gateways are not in this list
/// because Moonton does not publish them; the real ones come from the game's
/// own network logs via `HostStore.imported()`.
enum HostCatalog {

    static let moontonInfrastructure: [Host] = [
        Host(host: "mssdk.moonton.com", note: "Moonton SDK"),
        Host(host: "mssdk-new.moonton.com", note: "Moonton SDK (new)"),
        Host(host: "api.moonton.com", note: "Moonton API"),
        Host(host: "update.moonton.com", note: "update check"),
        Host(host: "ms-gw.moonton.com", note: "Moonton gateway"),
        Host(host: "ms-gw-new.moonton.com", note: "Moonton gateway (new)"),
        Host(host: "cdnsun.moonton.com", note: "CDN"),
        Host(host: "cdnapple.moonton.com", note: "Apple CDN")
    ]

    /// Garena distribution endpoints for the global MLBB build.
    static let garena: [Host] = [
        Host(host: "garena.com", note: "Garena"),
        Host(host: "accounts.garena.com", note: "Garena accounts"),
        Host(host: "mobile.ms.garena.com", note: "MLBB Garena distribution")
    ]

    static var builtIn: [Host] { moontonInfrastructure + garena }
}