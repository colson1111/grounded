import SwiftUI

struct UnifiedScheduleView: View {
    private let manager = BlockingManager.shared

    @State private var editingEntry: ScheduledWindowEntry?
    @State private var showProfilePicker = false
    @State private var addTargetProfile: BlockProfile?
    @State private var newBlock = ScheduleBlock(
        startMinuteOfDay: 9 * 60,
        endMinuteOfDay: ScheduleBlock.suggestedEnd(afterStart: 9 * 60),
        weekdays: [Calendar.current.component(.weekday, from: Date())]
    )

    private var entries: [ScheduledWindowEntry] {
        ScheduleWindowIndex.allEntries(from: manager.profiles)
    }

    private var overlaps: [(ScheduledWindowEntry, ScheduledWindowEntry)] {
        ScheduleWindowIndex.overlaps(in: entries)
    }

    private var conflictingEntryIDs: Set<String> {
        Set(overlaps.flatMap { [$0.0.id, $0.1.id] })
    }


    var body: some View {
        List {
            if !overlaps.isEmpty {
                Section {
                    ForEach(Array(overlaps.enumerated()), id: \.offset) { _, pair in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text("Time overlap")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.red)
                            }
                            HStack {
                                Text(pair.0.profile.name)
                                    .font(.subheadline.bold())
                                Text(pair.0.block.summary)
                                    .font(.subheadline)
                            }
                            HStack {
                                Text(pair.1.profile.name)
                                    .font(.subheadline.bold())
                                Text(pair.1.block.summary)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.red.opacity(0.08))
                    }
                } header: {
                    Label("Schedule conflicts", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } footer: {
                    Text("Both windows will try to activate at their start times, which can cause unpredictable switching. Adjust the times so they don't overlap.")
                        .foregroundStyle(.red.opacity(0.8))
                }
            }

            if entries.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No schedules yet",
                        systemImage: "clock",
                        description: Text("Tap + to add a time window and assign it to a profile.")
                    )
                }
            } else {
                Section("All windows") {
                    ForEach(entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.profile.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(entry.block.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if conflictingEntryIDs.contains(entry.id) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                } else {
                                    Text(entry.block.isEnabled ? "On" : "Off")
                                        .font(.caption.bold())
                                        .foregroundStyle(entry.block.isEnabled ? GroundedTheme.calmGreen : .secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(conflictingEntryIDs.contains(entry.id) ? Color.red.opacity(0.06) : nil)
                    }
                    .onDelete(perform: deleteEntries)
                }
            }

            Section {
                Text("Schedules use your device's local time. Windows must be at least 15 minutes and cannot cross midnight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .groundedListScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    prepareNewBlock()
                    showProfilePicker = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(manager.profiles.isEmpty)
            }
        }
        .sheet(item: $editingEntry) { entry in
            ScheduleBlockEditor(
                block: entry.block,
                onSave: { updated in saveBlock(updated, for: entry.profile) },
                onDelete: { deleteBlock(entry.block, from: entry.profile) }
            )
        }
        .sheet(isPresented: $showProfilePicker) {
            NavigationStack {
                List(manager.profiles) { profile in
                    Button(profile.name) {
                        addTargetProfile = profile
                        showProfilePicker = false
                    }
                    .foregroundStyle(.primary)
                }
                .navigationTitle("Add to profile")
                .navigationBarTitleDisplayMode(.inline)
                .groundedListScreen()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showProfilePicker = false }
                    }
                }
            }
        }
        .sheet(item: $addTargetProfile) { profile in
            ScheduleBlockEditor(
                block: newBlock,
                onSave: { block in
                    var updated = profile
                    updated.scheduleBlocks.append(block)
                    manager.saveProfile(updated)
                    addTargetProfile = nil
                },
                onDelete: nil
            )
        }
    }

    private func prepareNewBlock() {
        let cal = Calendar.current
        let minuteOfDay = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
        let start = min(max(minuteOfDay, 0), 1380)
        newBlock = ScheduleBlock(
            startMinuteOfDay: start,
            endMinuteOfDay: ScheduleBlock.suggestedEnd(afterStart: start),
            weekdays: [cal.component(.weekday, from: Date())]
        )
    }

    private func saveBlock(_ block: ScheduleBlock, for profile: BlockProfile) {
        var updated = profile
        if let idx = updated.scheduleBlocks.firstIndex(where: { $0.id == block.id }) {
            updated.scheduleBlocks[idx] = block
        } else {
            updated.scheduleBlocks.append(block)
        }
        manager.saveProfile(updated)
    }

    private func deleteBlock(_ block: ScheduleBlock, from profile: BlockProfile) {
        var updated = profile
        updated.scheduleBlocks.removeAll { $0.id == block.id }
        manager.saveProfile(updated)
    }

    private func deleteEntries(at offsets: IndexSet) {
        for idx in offsets {
            let entry = entries[idx]
            deleteBlock(entry.block, from: entry.profile)
        }
    }
}
