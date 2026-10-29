import SwiftUI
import SwiftData

/// 截图 → 候选任务 → 用户逐条确认。默认全选，改完点「添加」才落库。
struct CaptureReviewSheet: View {
    let draft: CaptureSession.Draft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.saveShotToEvidence) private var keepScreenshot = true

    @Query(sort: \TodoList.sortIndex) private var lists: [TodoList]

    @State private var rows: [Row]
    @State private var singleOnly = false
    @State private var targetListID: UUID?

    struct Row: Identifiable {
        let id = UUID()
        var isSelected: Bool
        var title: String
        var dueDate: Date?
        var hasTime: Bool
        var place: String
    }

    init(draft: CaptureSession.Draft) {
        self.draft = draft
        _rows = State(initialValue: draft.tasks.map {
            Row(
                isSelected: !$0.isEmptyTitle,
                title: $0.title,
                dueDate: $0.dueDate,
                hasTime: $0.hasTime,
                place: $0.place ?? ""
            )
        })
    }

    private var selectedCount: Int {
        rows.filter { $0.isSelected && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if rows.isEmpty {
                    Section {
                        EmptyHint(
                            symbol: "text.viewfinder",
                            title: String(localized: "Nothing recognised"),
                            message: String(localized: "Try a screenshot with clearer text.")
                        )
                    }
                } else {
                    Section {
                        Picker("How many", selection: $singleOnly) {
                            Text("All of them").tag(false)
                            Text("Just one").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: singleOnly) { _, single in
                            if single, let first = rows.firstIndex(where: \.isSelected) {
                                for index in rows.indices { rows[index].isSelected = (index == first) }
                            }
                        }
                    }

                    Section {
                        ForEach($rows) { $row in
                            rowView($row)
                        }
                    } header: {
                        Text("Found \(rows.count)")
                    } footer: {
                        Text("Empty fields are optional — fill them later or leave them blank.")
                            .font(.footnote)
                    }

                    Section {
                        listPicker
                    }
                }
            }
            .groupedRows()
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Add from screenshot")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedCount)") { addAll() }
                        .disabled(selectedCount == 0)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(_ row: Binding<Row>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    row.isSelected.wrappedValue.toggle()
                } label: {
                    Image(systemName: row.isSelected.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(row.isSelected.wrappedValue ? Theme.accent : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                TextField("Task", text: row.title)
                    .font(.system(size: 16, weight: .medium))
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let due = row.dueDate.wrappedValue {
                    DatePicker(
                        "",
                        selection: Binding(get: { due }, set: { row.dueDate.wrappedValue = $0 }),
                        // 只有识别到时间才给时间选择器，否则「18:06」会是凭空造出来的。
                        displayedComponents: row.hasTime.wrappedValue ? [.date, .hourAndMinute] : [.date]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)

                    Button {
                        row.dueDate.wrappedValue = nil
                        row.hasTime.wrappedValue = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Optional")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("", text: row.place, prompt: Text("Optional").foregroundStyle(.tertiary))
                    .font(.system(size: 13))
            }
        }
        .padding(.vertical, 2)
    }

    private var listPicker: some View {
        Picker("Add to", selection: Binding(
            get: { targetListID ?? lists.first?.uid },
            set: { targetListID = $0 }
        )) {
            ForEach(lists) { list in
                Label(list.title, systemImage: list.symbol).tag(Optional(list.uid))
            }
        }
    }

    // MARK: - Save

    private func addAll() {
        let chosenList = lists.first { $0.uid == (targetListID ?? lists.first?.uid) }
        var nextIndex = (chosenList?.tasks ?? []).map(\.sortIndex).max().map { $0 + 1 } ?? 0
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        for row in rows where row.isSelected {
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            // 没时间 → 今天；有时间 → 落在那一天并带上时间。
            let due = row.dueDate ?? today
            let task = TodoItem(
                title: title,
                dueDate: due,
                hasDueTime: row.dueDate != nil && row.hasTimeEffective,
                list: chosenList,
                sortIndex: nextIndex
            )
            context.insert(task)
            nextIndex += 1

            let place = row.place.trimmingCharacters(in: .whitespacesAndNewlines)
            if !place.isEmpty {
                context.insert(Evidence(kind: .place, text: place, task: task))
            }
            if keepScreenshot, let image = draft.imageData {
                // 原图动辄几 MB，存进库之前先压一下；备份时还会再压一次。
                context.insert(Evidence(
                    kind: .image,
                    text: String(localized: "Screenshot"),
                    imageData: ImageShrink.jpeg(image) ?? image,
                    task: task
                ))
            }
        }

        WorkspaceService.save(context)
        finish()
    }

    private func finish() {
        CaptureSession.shared.clear()
        dismiss()
    }
}

private extension CaptureReviewSheet.Row {
    /// 用户没手动关掉时间就当作带时间。
    var hasTimeEffective: Bool { hasTime }
}
