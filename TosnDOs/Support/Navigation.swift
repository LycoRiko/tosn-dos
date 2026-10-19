import Foundation

/// The five places the app can show. Deliberately small — everything else in
/// the UI is reachable in at most two taps from here.
enum SmartList: String, CaseIterable, Identifiable, Hashable, Codable {
    case today
    case upcoming
    case all
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return String(localized: "Today")
        case .upcoming: return String(localized: "Upcoming")
        case .all: return String(localized: "All")
        case .completed: return String(localized: "Completed")
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .upcoming: return "calendar"
        case .all: return "square.stack.3d.up"
        case .completed: return "checkmark.circle"
        }
    }
}

/// A stable sidebar / navigation selection.
///
/// Lists and tags are referenced by their own `uid` instead of by object
/// identity, so a selection never dangles after a delete or a CloudKit merge.
enum SidebarItem: Hashable, Identifiable {
    case smart(SmartList)
    case list(UUID)
    case tag(UUID)
    case templates

    var id: String {
        switch self {
        case .smart(let smart): return "smart.\(smart.rawValue)"
        case .list(let uid): return "list.\(uid.uuidString)"
        case .tag(let uid): return "tag.\(uid.uuidString)"
        case .templates: return "templates"
        }
    }

    var smartList: SmartList? {
        if case .smart(let smart) = self { return smart }
        return nil
    }

    var listUID: UUID? {
        if case .list(let uid) = self { return uid }
        return nil
    }

    var tagUID: UUID? {
        if case .tag(let uid) = self { return uid }
        return nil
    }
}
