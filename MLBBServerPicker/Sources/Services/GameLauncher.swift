import Foundation
import UIKit

/// Launches MLBB, falling back to the store when it isn't installed.
@MainActor
enum GameLauncher {

    private static let schemes = ["mobilelegends://", "mlbb://"]

    static func isInstalled() -> Bool {
        schemes.contains { UIApplication.shared.canOpenURL(URL(string: $0)!) }
    }

    @discardableResult
    static func launch() -> Bool {
        for scheme in schemes {
            guard let url = URL(string: scheme) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return true
            }
        }
        return false
    }

    static func openStore(for region: Region) {
        guard let url = URL(string: region.storeURL) else { return }
        UIApplication.shared.open(url)
    }
}