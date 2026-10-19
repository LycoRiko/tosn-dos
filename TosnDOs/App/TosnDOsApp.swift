import SwiftUI

@main
struct TosnDOsApp: App {
    init() {
        Prefs.registerDefaults()
    }

    #if os(macOS)
    private var mainScene: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(AppContainer.boot.container)
        }
        .defaultSize(width: 1080, height: 700)
        .commands {
            SidebarCommands()
        }
    }
    #else
    private var mainScene: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(AppContainer.boot.container)
        }
    }
    #endif

    @SceneBuilder
    var body: some Scene {
        mainScene

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 500, height: 640)
        }
        #endif
    }
}

/// Picks the platform shell and owns the two global settings that must apply
/// before anything else renders: appearance and first-launch seeding.
struct RootView: View {
    @AppStorage(PreferenceKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(PreferenceKey.hasOnboarded) private var hasOnboarded = false

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var repeatPrompt: RepeatService.Prompt?

    var body: some View {
        Group {
            if hasOnboarded {
                #if os(macOS)
                MacRootView()
                #else
                PhoneRootView()
                #endif
            } else {
                OnboardingView()
            }
        }
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
        .task {
            #if os(iOS)
            PhoneWatchSync.shared.start(context: context)
            #endif
            checkRepeat()
        }
        .onChange(of: scenePhase) { _, phase in
            // The watch may have been asleep through several edits; hand it the
            // newest picture whenever we come back to the front.
            if phase == .active {
                #if os(iOS)
                PhoneWatchSync.shared.pushSnapshot()
                #endif
                checkRepeat()
            }
        }
        .alert(repeatPrompt?.title ?? "", isPresented: repeatAlertShown) {
            if let prompt = repeatPrompt {
                if prompt.count == 1 {
                    Button("Add it") { resolve(.latest, prompt) }
                } else {
                    Button("Add just one") { resolve(.latest, prompt) }
                    Button(allButtonLabel(prompt)) { resolve(.all, prompt) }
                }
                Button("Don't add", role: .cancel) { resolve(.skip, prompt) }
            }
        } message: {
            if let prompt = repeatPrompt {
                Text(repeatMessage(prompt))
            }
        }
    }

    // MARK: - Repeating templates

    /// Says what the list is, why it is asking now, and leaves the numbers to
    /// the buttons — an alert body is the wrong place for a count.
    private func repeatMessage(_ prompt: RepeatService.Prompt) -> String {
        let cadence: String
        switch prompt.rule {
        case .daily: cadence = String(localized: "This list is made every day.")
        case .weekly: cadence = String(localized: "This list is made every week.")
        case .monthly: cadence = String(localized: "This list is made every month.")
        case .off: cadence = ""
        }

        let previous: String
        if let last = prompt.lastHandled {
            previous = String(localized: "The last one was \(last.formatted(.dateTime.month(.abbreviated).day())).")
        } else {
            previous = String(localized: "No list has been made from it yet.")
        }

        return "\(cadence)\n\(previous)"
    }

    private func allButtonLabel(_ prompt: RepeatService.Prompt) -> String {
        let unit: String
        switch prompt.rule {
        case .daily: unit = String(localized: "days")
        case .weekly: unit = String(localized: "weeks")
        case .monthly: unit = String(localized: "months")
        case .off: unit = String(localized: "lists")
        }
        return String(localized: "Add all \(prompt.count) \(unit)")
    }

    private var repeatAlertShown: Binding<Bool> {
        Binding(
            get: { repeatPrompt != nil },
            set: { if !$0 { repeatPrompt = nil } }
        )
    }

    private func checkRepeat() {
        guard hasOnboarded, repeatPrompt == nil else { return }
        repeatPrompt = RepeatService.nextPrompt(in: context)
    }

    private func resolve(_ choice: RepeatService.Choice, _ prompt: RepeatService.Prompt) {
        RepeatService.resolve(choice, for: prompt, in: context)
        repeatPrompt = nil
        // Another template may also be due; let this alert finish dismissing
        // first so the next one has something to present from.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            checkRepeat()
        }
    }
}
