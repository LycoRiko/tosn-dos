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
                LabeledContent("Version") {
                    Text(version)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Settings")
    }
}
