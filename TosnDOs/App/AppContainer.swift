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

        var detail: String {
            switch self {
            case .iCloud:
                return String(localized: "Your lists stay in sync across your devices and appear in the widget.")
            case .deviceOnly:
                return String(localized: "Your lists are saved on this device. Nothing is uploaded, and nothing is lost.")
            }
        }
    }
}
