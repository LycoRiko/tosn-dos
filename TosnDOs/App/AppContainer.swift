import Foundation
import SwiftData

/// Process-wide store, booted once.
@MainActor
enum AppContainer {
    static let boot: StoreBoot = SharedStore.boot()

    static var container: ModelContainer { boot.container }

    static var status: SyncStatus { boot.usesCloudKit ? .iCloud : .deviceOnly }

    enum SyncStatus {
        case iCloud
        case deviceOnly

        var isCloud: Bool { self == .iCloud }

        var title: String {
            switch self {
            case .iCloud: return String(localized: "On")
            case .deviceOnly: return String(localized: "On this device")
            }
        }
    }
}
