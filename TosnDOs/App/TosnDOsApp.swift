import SwiftUI
import SwiftData
import UserNotifications

@main
struct TosnDOsApp: App {
    init() {
        Prefs.registerDefaults()
        NotificationService.registerCategories()
        // Must be set before launch finishes, or cold-start actions are dropped.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared

        #if DEBUG
        if CommandLine.arguments.contains("-seedLedgerDemo") {
            LedgerDemo.seed(AppContainer.boot.container.mainContext)
        }
        #endif
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
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { UndoCenter.shared.perform() }
                    .keyboardShortcut("z", modifiers: .command)
            }
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
    @State private var capture = CaptureSession.shared

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
        .overlay(alignment: .bottom) { UndoBanner() }
        .preferredColorScheme(AppearanceMode(rawValue: appearanceRaw)?.colorScheme)
        .task {
            #if os(iOS)
            PhoneWatchSync.shared.start(context: context)
            #endif
            TimeMerge.runIfNeeded(context)
            #if DEBUG && os(iOS)
            if CommandLine.arguments.contains("-activityDemo") {
                ActivityDemo.seed(context)
            }
            #endif
            #if DEBUG
            if CommandLine.arguments.contains("-seedLedgerDemo") {
                LedgerDemo.seed(context)
            }
            #endif
            checkRepeat()
        }
        .onChange(of: scenePhase) { _, phase in
            // The watch may have been asleep through several edits; hand it the
            // newest picture whenever we come back to the front.
            // Flush staged deletions on the way out.
            if phase != .active {
                UndoCenter.shared.flush()
            }
            if phase == .active {
                LiveActivityService.reconcile(
                    (try? context.fetch(FetchDescriptor<TodoItem>())) ?? []
                )
                #if os(iOS)
                PhoneWatchSync.shared.pushSnapshot()
                #endif
                checkRepeat()
            }
        }
        .sheet(isPresented: Binding(
            get: { capture.draft != nil },
            set: { if !$0 { capture.clear() } }
        )) {
            if let draft = capture.draft {
                CaptureReviewSheet(draft: draft)
            }
        }
        .confirmationDialog(
            repeatPrompt?.title ?? "",
            isPresented: repeatAlertShown,
            titleVisibility: .visible
        ) {
            if let prompt = repeatPrompt {
                Button(latestLabel) { resolve(.latest, prompt) }
                if prompt.count > 1 {
                    Button(allLabel(prompt)) { resolve(.all, prompt) }
                }
                Button(skipLabel, role: .cancel) { resolve(.skip, prompt) }
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

        // Saying what happens to the periods left behind is the point of the prompt:
        // silence here is what made "skip" feel like it had no consequence.
        let leftBehind = prompt.count > 1
            ? String(localized: "Periods you do not catch up are recorded as skipped and will not be asked about again.")
            : ""

        return [cadence, previous, leftBehind].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private var latestLabel: String {
        String(localized: "Catch up the latest — 1 list")
    }

    private func allLabel(_ prompt: RepeatService.Prompt) -> String {
        String(localized: "Catch up all \(prompt.count) — \(prompt.count) lists")
    }

    private var skipLabel: String {
        String(localized: "Skip these — they will not be asked again")
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
