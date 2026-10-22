import SwiftUI

/// In-app mirror of the same preferences exposed in the system Settings app.
/// Both surfaces write the same `UserDefaults` keys, so they can never drift.
struct SettingsView: View {
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system.rawValue
    @AppStorage(PreferenceKey.showCompleted) private var showCompleted = true
    @AppStorage(PreferenceKey.templateDueToday) private var templateDueToday = true
    @AppStorage(BackgroundKey.imageName) private var backgroundImage = ""
    @AppStorage(BackgroundKey.blur) private var backgroundBlur = 24.0
    @AppStorage(BackgroundKey.opacity) private var backgroundOpacity = 0.92

    @Environment(\.modelContext) private var context
    @State private var exportDocument = BackupDocument()
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var pendingBackup: BackupFile?
    @State private var showsModePrompt = false
    @State private var backupNote: String?

    private var syncStatus: AppContainer.SyncStatus { AppContainer.status }

    private var background: Binding<BackgroundSetting> {
        Binding(
            get: {
                BackgroundSetting(
                    imageName: backgroundImage,
                    blur: backgroundBlur,
                    opacity: backgroundOpacity
                )
            },
            set: { value in
                backgroundImage = value.imageName
                backgroundBlur = value.blur
                backgroundOpacity = value.opacity
            }
        )
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - Backup

    private func exportBackup() {
        let file = BackupFile.capture(from: context)
        guard let data = try? file.data() else { return }
        exportDocument = BackupDocument(data: data)
        showsExporter = true
    }

    private func loadBackup(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard
            let data = try? Data(contentsOf: url),
            let file = try? BackupFile.decode(data)
        else {
            backupNote = String(localized: "That file could not be read.")
            return
        }
        pendingBackup = file
        showsModePrompt = true
    }

    private func restore(_ mode: BackupFile.Mode) {
        guard let backup = pendingBackup else { return }
        let counts = backup.restore(into: context, mode: mode)
        backupNote = String(localized: "Restored \(counts.lists) lists and \(counts.templates) templates.")
        pendingBackup = nil
    }

    /// Language only. `Locale.current.identifier` carries the region too, which
    /// reads as "English (China Mainland)" — nobody picks a language by region.
    /// The script is kept only for Chinese, where it is what distinguishes
    /// Simplified from Traditional; for everything else it adds "English (Latin)".
    private var languageName: String {
        let language = Locale.current.language
        let code = language.languageCode?.identifier ?? "en"
        let script = language.script?.identifier
        let identifier = (script == "Hans" || script == "Hant") ? "\(code)-\(script ?? "")" : code
        return Locale.current.localizedString(forIdentifier: identifier) ?? code
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                BackgroundPicker(setting: background)
            } header: {
                Text("Background")
            } footer: {
                Text("Shown on every screen that does not have its own photo.")
            }

            Section {
                Toggle("Show completed tasks", isOn: $showCompleted)
                Toggle("New lists from templates start today", isOn: $templateDueToday)
            } header: {
                Text("Tasks")
            } footer: {
                #if os(iOS)
                Text("These switches are also available in Settings › Tos'n DOs.")
                #else
                Text("These switches apply to every window and are shared with iCloud.")
                #endif
            }

            Section {
                LabeledContent("Language") {
                    Text(languageName)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("To change the language, open the Settings app and choose Tos'n DOs.")
            }

            Section {
                LabeledContent("Sync") {
                    Text(syncStatus.title)
                        .foregroundStyle(syncStatus.isCloud ? Theme.mint : .secondary)
                }
            } header: {
                Text("Sync")
            } footer: {
                Text(syncStatus.detail)
            }

            Section {
                Button("Export backup") { exportBackup() }
                Button("Restore backup") { showsImporter = true }
                if let backupNote {
                    Text(backupNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("One JSON file with every list and template. Restoring asks whether to merge or replace.")
            }

            Section {
                LabeledContent("Version") {
                    Text(version)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("About")
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "tosndos-backup"
        ) { _ in }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            loadBackup(result)
        }
        .confirmationDialog(
            "How should this backup be restored?",
            isPresented: $showsModePrompt,
            titleVisibility: .visible
        ) {
            Button("Merge with what's here") { restore(.merge) }
            Button("Replace everything", role: .destructive) { restore(.replace) }
            Button("Cancel", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("Merging adds every list as new. Replacing deletes what is here first.")
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Settings")
    }
}
