import Foundation
import SwiftData

struct StoreBoot {
    let container: ModelContainer
    let isShared: Bool
    let usesCloudKit: Bool
}

/// One place that knows where the database lives.
///
/// The store sits in an App Group container so the widget extension opens the
/// exact same file as the app. If the group (or CloudKit) is unavailable —
/// for example on an unsigned build — everything degrades to a local store
/// instead of failing to launch.
enum SharedStore {
    static let appGroupID = "group.com.rikomiyazaki.TosnDOs"
    static let storeName = "TosnDOs"

    static var schema: Schema {
        Schema([
            TodoList.self,
            TodoItem.self,
            Evidence.self,
            Subtask.self,
            Tag.self,
            ListTemplate.self,
            TemplateItem.self,
            TemplateCheck.self
        ])
    }

    static var sharedDirectory: URL? {
        #if os(iOS) || os(watchOS)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        #else
        // The macOS build is unsigned, so it owns no group container. Asking
        // for one makes macOS prompt for access to another app's data, so the
        // desktop version deliberately skips it and keeps a local store.
        return nil
        #endif
    }

    static var storeURL: URL {
        let directory = sharedDirectory
            ?? URL.applicationSupportDirectory.appending(path: storeName)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "\(storeName).store")
    }

    static func boot() -> StoreBoot {
        let schema = schema
        let url = storeURL
        let isShared = sharedDirectory != nil

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .automatic)]
        ) {
            return StoreBoot(container: container, isShared: isShared, usesCloudKit: isShared)
        }

        if let container = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
        ) {
            return StoreBoot(container: container, isShared: isShared, usesCloudKit: false)
        }

        // Last resort: an in-memory store keeps the UI usable instead of crashing.
        // It also means the user sees an empty app while their real data sits on
        // disk, so say it out loud rather than letting it look like a fresh setup.
        let message = "TosnDOs: both stores failed, running in memory. Nothing will be saved."
        print("⚠️ \(message)")
        assertionFailure(message)
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [memory]) {
            return StoreBoot(container: container, isShared: false, usesCloudKit: false)
        }

        fatalError("Unable to create the SwiftData container.")
    }

    /// Used by previews and, on a brand-new install, by the sample seeder.
    static func previewContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
}
