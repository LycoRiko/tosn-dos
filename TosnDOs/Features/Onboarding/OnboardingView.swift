import SwiftUI

/// First launch only. Four screens, no sign-up and no tour of features the
/// user has not asked for yet. The last screen is where notifications are
/// requested, because that is the only permission the app ever needs.
struct OnboardingView: View {
    @AppStorage(PreferenceKey.hasOnboarded) private var hasOnboarded = false
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let message: String
    }

    private var pages: [Page] {
        [
            Page(
                id: 0,
                symbol: "checkmark.circle.fill",
                title: String(localized: "One list. Today."),
                message: String(localized: "Tos'n DOs shows what is due now and keeps everything else one tap away.")
            ),
            Page(
                id: 1,
                symbol: "text.cursor",
                title: String(localized: "Type it, it's added"),
                message: String(localized: "Write the task the way you would say it. Dates like 明天 or 3pm are understood — no forms, no pickers.")
            ),
            Page(
                id: 2,
                symbol: "square.on.square.dashed",
                title: String(localized: "Templates you write once"),
                message: String(localized: "Save a checklist as a template, then pull a fresh copy whenever you need to run it again.")
            ),
            Page(
                id: 3,
                symbol: "bell.badge",
                title: String(localized: "A nudge before the deadline"),
                message: String(localized: "Give a list a deadline and Tos'n DOs can remind you before it arrives. Notifications are the only thing the app asks for.")
            )
        ]
    }

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                pager

                VStack(spacing: 12) {
                    HStack(spacing: 7) {
                        ForEach(pages) { item in
                            Capsule()
                                .fill(item.id == page ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.15)))
                                .frame(width: item.id == page ? 20 : 7, height: 7)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
                        }
                    }
                    .accessibilityHidden(true)

                    Button(isLast ? "Allow reminders" : "Continue") {
                        if isLast {
                            requestReminders()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .padding(.horizontal, 32)

                    if isLast {
                        Button("Not now") { finish() }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 26)
            }
            .frame(maxWidth: 520, maxHeight: 660)
        }
        .overlay(alignment: .topTrailing) {
            Button("Skip") {
                finish()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .opacity(isLast ? 0 : 1)
            .disabled(isLast)
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    @ViewBuilder
    private var pager: some View {
        #if os(iOS)
        TabView(selection: $page) {
            ForEach(pages) { item in
                pageView(item)
                    .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: page)
        #else
        pageView(pages[min(page, pages.count - 1)])
        #endif
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 104, height: 104)
                    .shadow(color: Theme.accent.opacity(0.3), radius: 24, y: 12)
                Image(systemName: item.symbol)
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 10) {
                Text(item.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(item.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if item.id == 1 {
                quickAddSample
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
    }

    /// A static preview of the composer, so the promise is visible rather than
    /// described. Nothing here is interactive.
    private var quickAddSample: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: Circle())

            Text("Buy coffee beans")
                .font(.subheadline)

            MetaChip(icon: "calendar", text: String(localized: "Tomorrow"), tint: Theme.accent)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: Circle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(radius: 24)
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }

    private func requestReminders() {
        Task {
            _ = await NotificationService.requestAuthorization()
            finish()
        }
    }

    private func finish() {
        withAnimation(.easeInOut(duration: 0.25)) {
            hasOnboarded = true
        }
    }
}
