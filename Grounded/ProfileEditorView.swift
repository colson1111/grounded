import SwiftUI
import FamilyControls
import ManagedSettings

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    private let manager = BlockingManager.shared

    private let editingID: String?

    @State private var name: String
    @State private var selectedAppIDs: Set<String>
    @State private var customDomains: [String]
    @State private var newDomain: String = ""
    @State private var anchorObjects: [String]
    @State private var activitySelection: FamilyActivitySelection
    @State private var showActivityPicker = false
    @State private var showAnchorCamera = false
    @State private var showLabelBrowser = false
    @State private var isAnchorPickerClosing = false
    @State private var showDeleteConfirm = false
    @State private var isPresetAppsExpanded = false
    @State private var isAppPickerExpanded = false
    @State private var isObjectRulesExpanded = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isScheduleExpanded = false
    @State private var scheduleBlocks: [ScheduleBlock]
    @State private var editingScheduleBlock: ScheduleBlock?
    @State private var showAdvancedSections = false
    @State private var hasUnlockedAppBlockingEdit = false
    @State private var showAnchorVerification = false
    @State private var showEditBlockedWhileActiveAlert = false
    @State private var originalActivitySelectionData: Data?
    @State private var originalActivityIncludeEntireCategory = false
    @State private var allowedApplicationTokensData: Data?
    @State private var originalAllowedApplicationTokensData: Data?
    @State private var category: ProfileCategory

    private var isEditingActiveProfile: Bool {
        guard let editingID else { return false }
        return manager.activeState.profile.id == editingID && manager.activeState.profile.isActive
    }

    private var isAppBlockingEditLocked: Bool {
        isEditingActiveProfile && !hasUnlockedAppBlockingEdit
    }

    init(editing profile: BlockProfile? = nil) {
        editingID = profile?.id
        _showAdvancedSections = State(initialValue: profile != nil)
        _name = State(initialValue: profile?.name ?? "")
        _category = State(initialValue: profile?.category ?? .focus)
        if let anchorObjects = profile?.anchorObjects, !anchorObjects.isEmpty {
            _anchorObjects = State(initialValue: VisionLabelCatalog.normalizedAnchorList(anchorObjects))
        } else {
            _anchorObjects = State(initialValue: [])
        }
        _scheduleBlocks = State(initialValue: profile?.scheduleBlocks ?? [])

        if let profile {
            _selectedAppIDs = State(initialValue: Self.inferSelectedApps(from: profile.blockedDomains))
            _customDomains = State(initialValue: Self.inferCustomDomains(from: profile.blockedDomains))
            if let decoded = ActivitySelectionHelpers.decodedSelection(
                from: profile.activitySelectionData,
                includeEntireCategory: profile.activityIncludeEntireCategory
            ) {
                _activitySelection = State(initialValue: decoded)
            } else {
                _activitySelection = State(initialValue: FamilyActivitySelection())
            }
            _originalActivitySelectionData = State(initialValue: profile.activitySelectionData)
            _originalActivityIncludeEntireCategory = State(initialValue: profile.activityIncludeEntireCategory)
            _allowedApplicationTokensData = State(initialValue: profile.allowedApplicationTokensData)
            _originalAllowedApplicationTokensData = State(initialValue: profile.allowedApplicationTokensData)
        } else {
            _selectedAppIDs = State(initialValue: [])
            _customDomains = State(initialValue: [])
            _activitySelection = State(initialValue: FamilyActivitySelection())
            _originalActivitySelectionData = State(initialValue: nil)
            _originalActivityIncludeEntireCategory = State(initialValue: false)
            _allowedApplicationTokensData = State(initialValue: nil)
            _originalAllowedApplicationTokensData = State(initialValue: nil)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                categorySection
                if showAdvancedSections {
                    appPickerDisclosureSection
                    presetDomainsDisclosureSection
                    scheduleDisclosureSection
                    objectRulesDisclosureSection
                    if editingID != nil { deleteSection }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading profile options…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(editingID == nil ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .groundedListScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showActivityPicker) {
                ActivityPickerSheet(selection: $activitySelection) { sessionRemovals, sessionReblocked in
                    allowedApplicationTokensData = ActivitySelectionHelpers.mergeAllowedExceptions(
                        existing: allowedApplicationTokensData,
                        sessionRemovals: sessionRemovals,
                        sessionReblocked: sessionReblocked
                    )
                }
            }
            .fullScreenCover(isPresented: $showAnchorVerification) {
                ObjectRecognitionView(
                    showsDismissControl: true,
                    verifyAnchorOnly: true,
                    onAnchorVerified: {
                        showAnchorVerification = false
                        hasUnlockedAppBlockingEdit = true
                    }
                )
            }
            .alert("Unlock required", isPresented: $showEditBlockedWhileActiveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This profile is active. Scan an anchor or turn blocking off before changing which apps are blocked.")
            }
            .sheet(item: $editingScheduleBlock) { block in
                ScheduleBlockEditor(
                    block: block,
                    onSave: { updated in
                        if let idx = scheduleBlocks.firstIndex(where: { $0.id == updated.id }) {
                            scheduleBlocks[idx] = updated
                        }
                    },
                    onDelete: {
                        scheduleBlocks.removeAll { $0.id == block.id }
                    }
                )
            }
            .fullScreenCover(isPresented: $showAnchorCamera) {
                AnchorLabelCaptureView { selected in
                    finishAnchorLabelSelection(selected)
                }
            }
            .sheet(isPresented: $showLabelBrowser) {
                LabelBrowserView { selected in
                    finishAnchorLabelSelection(selected)
                }
            }
            .onAppear {
                reloadActivitySelectionFromStore()
            }
            .task {
                VisionLabelCatalog.preloadTaxonomy()
                await Task.yield()
                showAdvancedSections = true
                if editingID == nil {
                    try? await Task.sleep(for: .milliseconds(250))
                    isNameFieldFocused = true
                }
            }
            .confirmationDialog("Delete this profile?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = editingID, let profile = manager.profiles.first(where: { $0.id == id }) {
                        manager.deleteProfile(profile)
                    }
                    dismiss()
                }
            }
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Profile Name") {
            TextField("e.g. Gaming, Morning", text: $name)
                .focused($isNameFieldFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private var categorySection: some View {
        Section("Profile Type") {
            Picker("Type", selection: $category) {
                ForEach(ProfileCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var appPickerDisclosureSection: some View {
        editorDisclosure("Block Specific Apps", systemImage: "iphone.slash", isExpanded: $isAppPickerExpanded) {
            appPickerContent
        }
    }

    private var appPickerContent: some View {
        let allowedCount = ActivitySelectionHelpers.decodeAllowedTokens(from: allowedApplicationTokensData).count
        let summary = AppBlockingSelectionSummary(
            activitySelection,
            allowedExceptionCount: allowedCount
        )

        return VStack(alignment: .leading, spacing: 14) {
            if isAppBlockingEditLocked {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Blocking now", systemImage: "shield.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(GroundedTheme.gentleRust)

                    Text("Scan your anchor to edit this list. To turn the profile off, use the camera from the main screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        showAnchorVerification = true
                    } label: {
                        Label("Scan Anchor to Edit", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GroundedTheme.calmGreen)
                }
            } else if summary.hasBlockingConfigured {
                appBlockingStatusBadge(blockingNow: isEditingActiveProfile)

                Text(summary.compactSummary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Tap Edit to change what’s blocked. With categories on, uncheck an app in the picker to allow it (e.g. Google Maps).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openActivityPicker()
                } label: {
                    Label("Edit Blocked Apps", systemImage: "pencil.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(GroundedTheme.calmGreen)
            } else {
                Text("Choose which apps or categories to block when this profile is on.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    openActivityPicker()
                } label: {
                    Label("Choose Apps to Block", systemImage: "plus.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(GroundedTheme.calmGreen)
            }

            Text("Apple hides app names here for privacy — the picker is where you see and edit the full list.")
                .font(.caption)
                .foregroundStyle(GroundedTheme.softMist)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func appBlockingStatusBadge(blockingNow: Bool) -> some View {
        if blockingNow {
            Label("Blocking now", systemImage: "shield.fill")
                .font(.subheadline.bold())
                .foregroundStyle(GroundedTheme.gentleRust)
        } else {
            Label("Saved — not blocking", systemImage: "shield")
                .font(.subheadline.bold())
                .foregroundStyle(GroundedTheme.softMist)
        }
    }

    private func openActivityPickerIfAllowed() -> Bool {
        guard !isAppBlockingEditLocked else {
            showEditBlockedWhileActiveAlert = true
            return false
        }
        return true
    }

    private func reloadActivitySelectionFromStore() {
        guard let editingID,
              let profile = manager.profiles.first(where: { $0.id == editingID }),
              let decoded = ActivitySelectionHelpers.decodedSelection(
                  from: profile.activitySelectionData,
                  includeEntireCategory: profile.activityIncludeEntireCategory
              ) else { return }

        activitySelection = decoded
        originalActivitySelectionData = profile.activitySelectionData
        originalActivityIncludeEntireCategory = profile.activityIncludeEntireCategory
        allowedApplicationTokensData = profile.allowedApplicationTokensData
        originalAllowedApplicationTokensData = profile.allowedApplicationTokensData
    }

    private func openActivityPicker() {
        reloadActivitySelectionFromStore()
        guard openActivityPickerIfAllowed() else { return }

        activitySelection = ActivitySelectionHelpers.selectionForPicker(from: activitySelection)
        let allowedCount = ActivitySelectionHelpers.decodeAllowedTokens(from: allowedApplicationTokensData).count
        showActivityPicker = true
    }

    private var hasChangedActivitySelection: Bool {
        let currentData = ActivitySelectionHelpers.encodeSelection(activitySelection)
        return currentData != originalActivitySelectionData
            || activitySelection.includeEntireCategory != originalActivityIncludeEntireCategory
            || allowedApplicationTokensData != originalAllowedApplicationTokensData
    }

    private var presetDomainsDisclosureSection: some View {
        editorDisclosure("Block Web Domains", systemImage: "network", isExpanded: $isPresetAppsExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                blockAllContent
                Divider()
                categoryContent
                Divider()
                customDomainsContent
            }
        }
    }

    private var scheduleDisclosureSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isScheduleExpanded) {
                if isScheduleExpanded {
                    ScheduleTimelineView(blocks: $scheduleBlocks)
                        .padding(.vertical, 4)

                    if scheduleBlocks.isEmpty {
                        Text("Tap the timeline to add a time window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(scheduleBlocks) { block in
                            Button {
                                editingScheduleBlock = block
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(block.summary)
                                            .foregroundStyle(.primary)
                                        Text(block.isEnabled ? "Enabled" : "Disabled")
                                            .font(.caption)
                                            .foregroundStyle(block.isEnabled ? GroundedTheme.calmGreen : .secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    scheduleBlocks.removeAll { $0.id == block.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }

                    Text("Also editable in Settings → Schedule. Requires Screen Time permission on save. Minimum window: 15 min; cannot cross midnight. End time defaults to 1 hour after start.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } label: {
                Label("Schedule", systemImage: "clock")
            }
        }
    }

    private var objectRulesDisclosureSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isObjectRulesExpanded) {
                if isObjectRulesExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        anchorContent
                    }
                    .padding(.top, 8)
                }
            } label: {
                Label {
                    Text("Anchor Settings")
                        .font(.headline)
                } icon: {
                    GroundedAnchorIcon(size: 18)
                }
            }
        }
    }

    private func editorDisclosure<Content: View>(
        _ title: String,
        systemImage: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Section {
            DisclosureGroup(isExpanded: isExpanded) {
                if isExpanded.wrappedValue {
                    VStack(alignment: .leading, spacing: 12) {
                        content()
                    }
                    .padding(.top, 8)
                }
            } label: {
                Label(title, systemImage: systemImage)
                    .font(.headline)
            }
        }
    }

    private var blockAllContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Block All Known Apps' Domains", isOn: Binding(
                get: { Set(knownApps.map { $0.id }).isSubset(of: selectedAppIDs) },
                set: { on in
                    if on { selectedAppIDs = Set(knownApps.map { $0.id }) }
                    else { selectedAppIDs = [] }
                }
            ))
            Text("\(resolvedDomains.count) web domains will be blocked in Safari. This is separate from app icon blocking above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(appCategories) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.name)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Toggle("Block All \(category.name)", isOn: Binding(
                        get: { category.apps.allSatisfy { selectedAppIDs.contains($0.id) } },
                        set: { on in
                            for app in category.apps {
                                if on { selectedAppIDs.insert(app.id) }
                                else { selectedAppIDs.remove(app.id) }
                            }
                        }
                    ))
                    .bold()

                    ForEach(category.apps) { app in
                        Toggle(app.name, isOn: Binding(
                            get: { selectedAppIDs.contains(app.id) },
                            set: { on in
                                if on { selectedAppIDs.insert(app.id) }
                                else { selectedAppIDs.remove(app.id) }
                            }
                        ))
                        .padding(.leading, 8)
                    }
                }
            }
        }
    }

    private var customDomainsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Domains")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                TextField("e.g. superautopets.com", text: $newDomain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Add") { addCustomDomain() }
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(customDomains, id: \.self) { domain in
                Text(domain).foregroundStyle(.secondary)
            }
            .onDelete { customDomains.remove(atOffsets: $0) }
        }
    }

    private var anchorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anchor - Unlocks This Profile")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if anchorObjects.isEmpty {
                Text("No anchors yet. Add one with the camera or label browser.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(anchorObjects, id: \.self) { label in
                    Label {
                        Text(VisionLabelCatalog.displayName(label))
                    } icon: {
                        GroundedAnchorIcon(size: 14)
                    }
                    .foregroundStyle(GroundedTheme.calmGreen)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                anchorObjects.removeAll { $0 == label }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }

            Menu {
                Button {
                    guard !isAnchorPickerClosing else { return }
                    showAnchorCamera = true
                } label: {
                    Label("Detect with Camera", systemImage: "camera")
                }
                Button {
                    guard !isAnchorPickerClosing else { return }
                    showLabelBrowser = true
                } label: {
                    Label("Browse Vision Labels", systemImage: "list.bullet.rectangle")
                }
            } label: {
                Label("Add Anchor", systemImage: "plus.circle.fill")
            }
            .disabled(isAnchorPickerClosing)
            Text("Add one label at a time. Choose something inconvenient to reach — showing it to the camera will deactivate this profile.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Profile", role: .destructive) {
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - Helpers

    private var resolvedDomains: [String] {
        let appDomains = selectedAppIDs.flatMap { id in
            knownApps.first(where: { $0.id == id })?.domains ?? []
        }
        return Array(Set(appDomains + customDomains))
    }

    private func addCustomDomain() {
        let domain = Self.normalizedDomain(from: newDomain)
        guard !domain.isEmpty, !customDomains.contains(domain) else { return }
        customDomains.append(domain)
        newDomain = ""
    }

    private func addAnchorLabel(_ raw: String) {
        guard let label = VisionLabelCatalog.canonicalIdentifier(for: raw) else { return }
        guard !anchorObjects.contains(label) else { return }
        anchorObjects.append(label)
    }

    private func finishAnchorLabelSelection(_ selected: String) {
        addAnchorLabel(selected)
        isAnchorPickerClosing = true
        showAnchorCamera = false
        showLabelBrowser = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            isAnchorPickerClosing = false
        }
    }

    private func save() {
        if isAppBlockingEditLocked && hasChangedActivitySelection {
            showEditBlockedWhileActiveAlert = true
            return
        }

        let id = editingID ?? UUID().uuidString
        let selectionData = ActivitySelectionHelpers.encodeSelection(activitySelection)
        let allowedCount = ActivitySelectionHelpers.decodeAllowedTokens(from: allowedApplicationTokensData).count
        let wasActive = editingID.flatMap { id in
            manager.activeState.profile.id == id && manager.activeState.profile.isActive
        } ?? false
        let profile = BlockProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            isActive: wasActive,
            blockedDomains: resolvedDomains,
            activitySelectionData: selectionData,
            activityIncludeEntireCategory: activitySelection.includeEntireCategory,
            allowedApplicationTokensData: allowedApplicationTokensData,
            anchorObjects: VisionLabelCatalog.normalizedAnchorList(anchorObjects),
            scheduleBlocks: scheduleBlocks,
            category: category
        )
        Task {
            if !scheduleBlocks.isEmpty {
                _ = await manager.ensureScheduleAuthorization()
            }
            manager.saveProfile(profile)
            await MainActor.run { dismiss() }
        }
    }

    private static func inferSelectedApps(from domains: [String]) -> Set<String> {
        let domainSet = Set(domains)
        return Set(knownApps.compactMap { app in
            app.domains.contains(where: { domainSet.contains($0) }) ? app.id : nil
        })
    }

    private static func inferCustomDomains(from domains: [String]) -> [String] {
        let knownDomains = Set(knownApps.flatMap { $0.domains })
        return domains.filter { !knownDomains.contains($0) }
    }

    private static func normalizedDomain(from input: String) -> String {
        var value = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !value.contains("://") { value = "https://\(value)" }
        if let url = URL(string: value), let host = url.host {
            value = host
        } else if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

// MARK: - Schedule Timeline

struct ScheduleTimelineView: View {
    @Binding var blocks: [ScheduleBlock]
    @State private var editingBlock: ScheduleBlock?
    @State private var addingBlock = false
    @State private var tappedMinute: Int = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 44)

                // Hour ticks at 6am, noon, 6pm
                ForEach([6, 12, 18], id: \.self) { hour in
                    let x = CGFloat(hour) / 24.0 * geo.size.width
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1, height: 44)
                        .offset(x: x)
                }

                // Enabled blocks
                ForEach(blocks) { block in
                    let x = CGFloat(block.startMinuteOfDay) / 1440.0 * geo.size.width
                    let w = max(
                        CGFloat(block.endMinuteOfDay - block.startMinuteOfDay) / 1440.0 * geo.size.width,
                        4
                    )
                    RoundedRectangle(cornerRadius: 4)
                        .fill(block.isEnabled ? GroundedTheme.calmGreen.opacity(0.75) : Color.gray.opacity(0.35))
                        .frame(width: w, height: 36)
                        .offset(x: x, y: 4)
                        .onTapGesture { editingBlock = block }
                }

                // Invisible tap target for adding blocks
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: 44)
                    .onTapGesture { location in
                        let minute = Int(location.x / geo.size.width * 1440)
                        tappedMinute = min(max(minute, 0), 1380) // leave room for 1hr window
                        addingBlock = true
                    }
            }
        }
        .frame(height: 44)
        .sheet(item: $editingBlock) { block in
            ScheduleBlockEditor(
                block: block,
                onSave: { updated in
                    if let idx = blocks.firstIndex(where: { $0.id == updated.id }) {
                        blocks[idx] = updated
                    }
                },
                onDelete: {
                    blocks.removeAll { $0.id == block.id }
                }
            )
        }
        .sheet(isPresented: $addingBlock) {
            ScheduleBlockEditor(
                block: ScheduleBlock(
                    startMinuteOfDay: tappedMinute,
                    endMinuteOfDay: ScheduleBlock.suggestedEnd(afterStart: tappedMinute),
                    weekdays: [Calendar.current.component(.weekday, from: Date())]
                ),
                onSave: { newBlock in blocks.append(newBlock) },
                onDelete: nil
            )
        }
    }
}

// MARK: - Schedule Block Editor

struct ScheduleBlockEditor: View {
    @State var block: ScheduleBlock
    let onSave: (ScheduleBlock) -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Time") {
                    DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                }
                Section("Repeat on") {
                    WeekdayPicker(selection: $block.weekdays)
                }
                Section {
                    Toggle("Enabled", isOn: $block.isEnabled)
                }
                if let onDelete {
                    Section {
                        Button("Remove Block", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Schedule Block")
            .navigationBarTitleDisplayMode(.inline)
            .groundedListScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(block)
                        dismiss()
                    }
                    .disabled(block.weekdays.isEmpty ||
                              (block.endMinuteOfDay - block.startMinuteOfDay) < 15)
                }
            }
        }
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(block.startMinuteOfDay) },
            set: { newDate in
                block.startMinuteOfDay = dateToMinutes(newDate)
                block.alignEndAfterStartChange()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { minutesToDate(block.endMinuteOfDay) },
            set: { block.endMinuteOfDay = dateToMinutes($0) }
        )
    }

    private func minutesToDate(_ minutes: Int) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private func dateToMinutes(_ date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }
}

// MARK: - Weekday Chip Picker

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    // (weekday int, short label) — Calendar weekday 1=Sun … 7=Sat
    private let days: [(Int, String)] = [(1,"S"),(2,"M"),(3,"T"),(4,"W"),(5,"T"),(6,"F"),(7,"S")]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.0) { weekday, label in
                let chosen = selection.contains(weekday)
                Button {
                    if chosen { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(label)
                        .font(.caption.bold())
                        .frame(width: 34, height: 34)
                        .background(chosen ? GroundedTheme.calmGreen : Color.secondary.opacity(0.15),
                                    in: Circle())
                        .foregroundStyle(chosen ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Label Browser

struct LabelBrowserView: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? allVisionLabels : allVisionLabels.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.isEmpty {
                    ForEach(filteredVisionLabelCategories) { category in
                        Section(category.name) {
                            ForEach(category.labels, id: \.self) { label in
                                labelRow(label)
                            }
                        }
                    }
                } else {
                    ForEach(filtered, id: \.self) { label in
                        labelRow(label)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search objects...")
            .navigationTitle("Vision Labels")
            .navigationBarTitleDisplayMode(.inline)
            .groundedListScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func labelRow(_ label: String) -> some View {
        Button {
            onSelect(label)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                dismiss()
            }
        } label: {
            Text(VisionLabelCatalog.displayName(label))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - App Blocking Summary

struct AppBlockingSelectionSummary {
    let applicationCount: Int
    let categoryCount: Int
    let webDomainCount: Int
    let allowedExceptionCount: Int

    init(_ selection: FamilyActivitySelection, allowedExceptionCount: Int = 0) {
        applicationCount = selection.applicationTokens.count
        categoryCount = selection.categoryTokens.count
        webDomainCount = selection.webDomainTokens.count
        self.allowedExceptionCount = allowedExceptionCount
    }

    var hasBlockingConfigured: Bool {
        applicationCount > 0 || categoryCount > 0 || webDomainCount > 0
    }

    var detailLines: [String] {
        var lines: [String] = []
        if categoryCount > 0 {
            let noun = categoryCount == 1 ? "category" : "categories"
            lines.append("\(categoryCount) app \(noun) — blocks most apps on your device")
        }
        if categoryCount > 0 {
            if allowedExceptionCount > 0 {
                let noun = allowedExceptionCount == 1 ? "app" : "apps"
                lines.append("\(allowedExceptionCount) \(noun) allowed through")
            }
        } else if applicationCount > 0 {
            let noun = applicationCount == 1 ? "app" : "apps"
            lines.append("\(applicationCount) \(noun) blocked individually")
        }
        if webDomainCount > 0 {
            let noun = webDomainCount == 1 ? "website" : "websites"
            lines.append("\(webDomainCount) Safari \(noun) blocked")
        }
        return lines
    }

    var footnote: String? {
        if categoryCount > 0 && allowedExceptionCount == 0 && applicationCount > 50 {
            return "Re-open the picker and uncheck each app you want to allow (e.g. Google Maps), then tap Done and Save — that records the exceptions blocking needs."
        }
        if categoryCount > 0 {
            return "Uncheck an app in the picker to allow it through. iOS may only show an hourglass on some blocked apps."
        }
        if applicationCount > 0 {
            return "These apps are blocked individually. Reopen the picker to review which apps are checked."
        }
        return nil
    }

    var shortProfileSummary: String {
        var parts: [String] = []
        if categoryCount > 0 {
            parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies") blocked")
            if allowedExceptionCount > 0 {
                parts.append("\(allowedExceptionCount) allowed")
            }
        } else if applicationCount > 0 {
            parts.append("\(applicationCount) app\(applicationCount == 1 ? "" : "s") blocked")
        } else if webDomainCount > 0 {
            parts.append("\(webDomainCount) Safari site\(webDomainCount == 1 ? "" : "s") blocked")
        } else {
            return "apps blocked"
        }
        return parts.joined(separator: " · ")
    }

    var compactSummary: String {
        detailLines.joined(separator: " · ")
    }
}

// MARK: - Activity Picker Sheet

struct ActivityPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    var onDone: ((Set<ApplicationToken>, Set<ApplicationToken>) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// Snapshot when the sheet opens so Cancel can restore the prior selection.
    @State private var backupSelection: FamilyActivitySelection?
    @State private var priorApplicationTokens: Set<ApplicationToken> = []
    @State private var sessionRemovals: Set<ApplicationToken> = []
    @State private var sessionReblocked: Set<ApplicationToken> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Checked categories block most apps. Uncheck any app you want to allow through, then tap Done.")
                    Text("If you use categories, apps you allowed may still appear unchecked in the list — that’s normal.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))

                FamilyActivityPicker(selection: $selection)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Blocked Apps")
            .navigationBarTitleDisplayMode(.inline)
            .groundedScreen()
            .onAppear {
                if backupSelection == nil {
                    backupSelection = selection
                    priorApplicationTokens = selection.applicationTokens
                }
            }
            .onChange(of: selection.applicationTokens) { _, newTokens in
                sessionRemovals.formUnion(priorApplicationTokens.subtracting(newTokens))
                sessionReblocked.formUnion(newTokens.subtracting(priorApplicationTokens))
                priorApplicationTokens = newTokens
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let backupSelection {
                            selection = backupSelection
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone?(sessionRemovals, sessionReblocked)
                        dismiss()
                    }
                }
            }
        }
    }
}
