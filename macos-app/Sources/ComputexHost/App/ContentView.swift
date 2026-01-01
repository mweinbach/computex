import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingIPSWPicker = false
    @State private var showingCheckpointSheet = false
    @State private var checkpointName = ""
    @State private var checkpointMode: CheckpointMode = .stateful
    @State private var showingCloneSheet = false
    @State private var cloneName = ""
    @State private var cloneSource: SessionCloneSource = .base

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task {
            await model.bootstrapIfNeeded()
        }
        .fileImporter(
            isPresented: $showingIPSWPicker,
            allowedContentTypes: [UTType(filenameExtension: "ipsw") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    model.importIPSW(url: url)
                }
            case .failure(let error):
                model.reportError(error)
            }
        }
        .sheet(isPresented: $showingCheckpointSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text(checkpointMode == .stateful ? "New Checkpoint" : "New Disk Checkpoint")
                    .font(.headline)
                TextField("Checkpoint name", text: $checkpointName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingCheckpointSheet = false
                    }
                    Button("Save") {
                        let name = checkpointName
                        showingCheckpointSheet = false
                        Task {
                            switch checkpointMode {
                            case .stateful:
                                await model.saveCheckpoint(name: name)
                            case .diskOnly:
                                await model.saveDiskCheckpoint(name: name)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        checkpointMode == .stateful
                            ? model.activeSessionID == nil
                            : model.selectedSessionID == nil || model.activeSessionID == model.selectedSessionID
                    )
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .sheet(isPresented: $showingCloneSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Clone Session")
                    .font(.headline)
                Picker("Source", selection: $cloneSource) {
                    ForEach(availableCloneSources) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.baseReady)

                TextField("Session name", text: $cloneName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingCloneSheet = false
                    }
                    Button("Clone") {
                        let name = cloneName
                        showingCloneSheet = false
                        Task { await model.cloneSession(name: name, source: cloneSource) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.baseReady)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
    }

    private var sidebar: some View {
        List {
            appStatusSection
            vmStatusSection
            sessionsSection
            checkpointsSection
            restoreImageSection
            ipswLibrarySection
            preferencesSection
            credentialsSection
            activeSelectionSection
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 260, ideal: 300)
    }

    private var detail: some View {
        VSplitView {
            ZStack {
                Group {
                    if let virtualMachine = model.virtualMachine {
                        VMDisplayView(virtualMachine: virtualMachine)
                            .background(Color.black)
                    } else {
                        MovingGradientPlaceholder()
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))

            VStack(spacing: 0) {
                HStack {
                    Label("Activity Log", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    Button {
                        model.logLines.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                Divider()

                List {
                    ForEach(Array(model.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                    }
                }
                .listStyle(.plain)
                .defaultScrollAnchor(.bottom)
            }
            .frame(minHeight: 120)
            .background(.background)
        }
        .navigationTitle("ComputexHost")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.virtualMachine != nil {
                    Button {
                        Task { await model.stopSession() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .tint(.red)
                    .help("Stop VM")
                }

                Menu {
                    managementActions
                    sessionActions
                    checkpointActions
                } label: {
                    Label("Actions", systemImage: "play.circle.fill")
                }
            }
        }
    }

    private var appStatusSection: some View {
        Section {
            LabeledContent {
                Text(model.status.label)
                    .foregroundStyle(model.status == .error ? .red : .secondary)
            } label: {
                Label("App Status", systemImage: "info.circle")
            }

            if model.isInstalling {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.installProgress)
                        .controlSize(.small)
                    Text("Installing: \(Int(model.installProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if model.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: model.downloadProgress)
                        .controlSize(.small)
                    Text("Downloading: \(Int(model.downloadProgress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("App")
        }
    }

    private var vmStatusSection: some View {
        Section {
            LabeledContent {
                Text(model.baseInstalled ? "Installed" : "Missing")
                    .foregroundStyle(model.baseInstalled ? .primary : .secondary)
            } label: {
                Label("Base VM", systemImage: "server.rack")
            }

            LabeledContent {
                Text(model.baseReady ? "Yes" : "No")
                    .foregroundStyle(model.baseReady ? .primary : .secondary)
            } label: {
                Label("Base Ready", systemImage: "checkmark.seal")
            }

            LabeledContent {
                Text(model.virtualMachine == nil ? "No" : "Yes")
                    .foregroundStyle(model.virtualMachine != nil ? .blue : .secondary)
            } label: {
                Label("Running", systemImage: "play.circle")
            }
        } header: {
            Text("VM Status")
        }
    }

    private var sessionsSection: some View {
        Section {
            if model.sessions.isEmpty {
                Text("No sessions yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.sessions) { session in
                    SessionRowView(
                        session: session,
                        isActive: model.activeSessionID == session.id,
                        isSelected: model.selectedSessionID == session.id
                    ) {
                        model.selectSession(id: session.id)
                    } onStart: {
                        Task { await model.startSelectedSession() }
                    }
                    .contextMenu {
                        Button("Start") {
                            Task { await model.startSelectedSession() }
                        }
                        .disabled(model.selectedSessionID != session.id || !model.baseReady)

                        Button("Save as Base") {
                            Task { await model.saveBaseFromSession(sessionID: session.id) }
                        }
                        .disabled(!model.baseReady)

                        Button(role: .destructive) {
                            Task { await model.deleteSession(id: session.id) }
                        } label: {
                            Text(session.kind == .primary ? "Reset Primary" : "Delete")
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let session = model.sessions[index]
                        Task { await model.deleteSession(id: session.id) }
                    }
                }
            }

            HStack {
                Button("Clone Session") {
                    cloneName = ""
                    cloneSource = .base
                    showingCloneSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.baseReady)

                Button("Recreate Primary") {
                    Task { await model.createPrimaryFromBase() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.baseReady)

                Button("Save Primary to Base") {
                    Task { await model.savePrimaryToBase() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!model.baseReady)
            }
        } header: {
            Text("Sessions")
        } footer: {
            Text("Select a session to browse checkpoints or start it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var checkpointsSection: some View {
        Section {
            if model.selectedSessionID == nil {
                Text("Select a session to see checkpoints.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.checkpoints.isEmpty {
                Text("No checkpoints yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.checkpoints) { checkpoint in
                    CheckpointRowView(
                        checkpoint: checkpoint,
                        isSelected: model.selectedCheckpointID == checkpoint.id
                    ) {
                        model.selectedCheckpointID = checkpoint.id
                    } onRestore: {
                        Task { await model.restoreCheckpoint(id: checkpoint.id) }
                    } onDelete: {
                        model.deleteCheckpoint(id: checkpoint.id)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let checkpoint = model.checkpoints[index]
                        model.deleteCheckpoint(id: checkpoint.id)
                    }
                }
            }

            HStack {
                Button("Save Checkpoint") {
                    checkpointName = ""
                    checkpointMode = .stateful
                    showingCheckpointSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.activeSessionID == nil || model.isSavingCheckpoint)

                Button("Save Disk Checkpoint") {
                    checkpointName = ""
                    checkpointMode = .diskOnly
                    showingCheckpointSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.selectedSessionID == nil || model.activeSessionID == model.selectedSessionID)

                Button("Open Folder") {
                    model.openCheckpointsFolder()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.selectedSessionID == nil)
            }
        } header: {
            Text("Checkpoints")
        } footer: {
            Text("Checkpoints include VM state plus a cloned disk image.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var restoreImageSection: some View {
        Section {
            LabeledContent {
                if model.isDownloading {
                    ProgressView(value: model.downloadProgress)
                        .controlSize(.small)
                        .frame(width: 80)
                } else {
                    Button(model.hasLatestRestoreImage ? "Redownload" : "Download") {
                        Task { await model.downloadLatestRestoreImage() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isDownloading)
                }
            } label: {
                Label("Latest", systemImage: "arrow.down.circle")
            }

            LabeledContent {
                Button("Choose...") {
                    showingIPSWPicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } label: {
                Label("Manual", systemImage: "doc.badge.plus")
            }

            LabeledContent {
                Button(model.isRefreshingCatalog ? "Refreshing" : "Refresh") {
                    Task { await model.refreshCatalog() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isRefreshingCatalog)
            } label: {
                Label("Catalog", systemImage: "sparkle.magnifyingglass")
            }

            if let lastUpdated = model.catalogCache.lastUpdated {
                HStack {
                    Text("Updated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(lastUpdated.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let error = model.catalogCache.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        } header: {
            Text("Restore Image")
        }
    }

    private var ipswLibrarySection: some View {
        Section {
            if model.storedIPSWs.isEmpty {
                Text("No IPSWs yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.storedIPSWs) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: entry.source == .latest ? "sparkles" : "shippingbox")
                            .foregroundStyle(entry.source == .latest ? .purple : Color.accentColor)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.versionLabel ?? entry.fileName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(entry.fileName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if model.restoreSelection?.storedID == entry.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectStoredIPSW(id: entry.id)
                    }
                    .contextMenu {
                        Button("Use") {
                            model.selectStoredIPSW(id: entry.id)
                        }
                        Button(role: .destructive) {
                            model.deleteStoredIPSW(id: entry.id)
                        } label: {
                            Text("Delete")
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        let entry = model.storedIPSWs[index]
                        model.deleteStoredIPSW(id: entry.id)
                    }
                }
            }

            Button("Open IPSW Folder") {
                model.openIPSWFolder()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } header: {
            Text("IPSW Library")
        }
    }

    private var preferencesSection: some View {
        Section {
            LabeledContent {
                Stepper(value: cpuBinding, in: 1...64, step: 1) {
                    Text("\(model.preferences.cpuCount) cores")
                }
            } label: {
                Label("CPU", systemImage: "cpu")
            }

            LabeledContent {
                Stepper(value: memoryBinding, in: 2...512, step: 2) {
                    Text("\(model.preferences.memoryGB) GB")
                }
            } label: {
                Label("Memory", systemImage: "memorychip")
            }

            LabeledContent {
                Stepper(value: diskBinding, in: 32...2048, step: 16) {
                    Text("\(model.preferences.diskGB) GB")
                }
            } label: {
                Label("Disk", systemImage: "internaldrive")
            }
        } header: {
            Text("Preferences")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("CPU and Memory changes apply on next boot.")
                Text("Disk changes apply when installing a new base VM.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
    }

    private var credentialsSection: some View {
        Section {
            LabeledContent {
                TextField("Username", text: usernameBinding)
                    .textFieldStyle(.roundedBorder)
            } label: {
                Label("Username", systemImage: "person")
            }

            LabeledContent {
                SecureField("Password", text: passwordBinding)
                    .textFieldStyle(.roundedBorder)
            } label: {
                Label("Password", systemImage: "key")
            }
        } header: {
            Text("VM Credentials")
        } footer: {
            Text("Stored locally for automation. You can change these anytime.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var activeSelectionSection: some View {
        Group {
            if let selection = model.restoreSelection {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(selection.label)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text(selection.url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Active Selection")
                }
            }
        }
    }

    private var managementActions: some View {
        Section("Management") {
            Button {
                Task { await model.installBaseFromSelection() }
            } label: {
                Label("Install Base VM", systemImage: "tray.and.arrow.down")
            }
            .disabled(model.restoreSelection == nil || model.isInstalling)

            Button {
                Task { await model.startBaseSetup() }
            } label: {
                Label("Boot Base Setup", systemImage: "hammer")
            }
            .disabled(!model.baseInstalled)

            Button {
                Task { await model.markBaseReady() }
            } label: {
                Label("Mark Base Ready", systemImage: "checkmark.seal")
            }
            .disabled(!model.needsBaseSetup)

            Button(role: .destructive) {
                model.resetBaseVM()
            } label: {
                Label("Reset Base VM", systemImage: "trash")
            }
            .disabled(model.virtualMachine != nil)
        }
    }

    private var sessionActions: some View {
        Section("Sessions") {
            Button {
                cloneName = ""
                cloneSource = .base
                showingCloneSheet = true
            } label: {
                Label("Clone Session", systemImage: "square.on.square")
            }
            .disabled(!model.baseReady)

            Button {
                Task { await model.createPrimaryFromBase() }
            } label: {
                Label("Recreate Primary", systemImage: "arrow.clockwise")
            }
            .disabled(!model.baseReady)

            Button {
                Task { await model.savePrimaryToBase() }
            } label: {
                Label("Save Primary to Base", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.baseReady)

            Button {
                Task { await model.startSelectedSession() }
            } label: {
                Label("Start Selected VM", systemImage: "play.circle")
            }
            .disabled(model.selectedSessionID == nil || !model.baseReady)

            Button {
                Task { await model.startPrimarySession() }
            } label: {
                Label("Start Primary VM", systemImage: "play.fill")
            }
            .disabled(!model.baseReady)

            Button {
                Task { await model.startDisposableSession() }
            } label: {
                Label("New Disposable VM", systemImage: "sparkles")
            }
            .disabled(!model.baseReady)

            if let sessionID = model.selectedSessionID {
                Button {
                    Task { await model.saveSelectedToBase() }
                } label: {
                    Label("Save Selected to Base", systemImage: "square.and.arrow.down")
                }

                Button(role: .destructive) {
                    Task { await model.deleteSession(id: sessionID) }
                } label: {
                    Label("Delete Selected VM", systemImage: "trash")
                }
            }
        }
    }

    private var checkpointActions: some View {
        Section("Checkpoints") {
            Button {
                checkpointName = ""
                checkpointMode = .stateful
                showingCheckpointSheet = true
            } label: {
                Label("Save Checkpoint", systemImage: "bookmark")
            }
            .disabled(model.activeSessionID == nil || model.isSavingCheckpoint)

            Button {
                checkpointName = ""
                checkpointMode = .diskOnly
                showingCheckpointSheet = true
            } label: {
                Label("Save Disk Checkpoint", systemImage: "bookmark")
            }
            .disabled(model.selectedSessionID == nil || model.activeSessionID == model.selectedSessionID)

            if let checkpointID = model.selectedCheckpointID {
                Button {
                    Task { await model.restoreCheckpoint(id: checkpointID) }
                } label: {
                    Label("Restore Selected", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.selectedSessionID == nil)
            }
        }
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { model.credentials.username },
            set: { model.updateCredentials(username: $0) }
        )
    }

    private var passwordBinding: Binding<String> {
        Binding(
            get: { model.credentials.password },
            set: { model.updateCredentials(password: $0) }
        )
    }

    private var cpuBinding: Binding<Int> {
        Binding(
            get: { model.preferences.cpuCount },
            set: { model.updatePreferences(cpuCount: $0) }
        )
    }

    private var memoryBinding: Binding<Int> {
        Binding(
            get: { model.preferences.memoryGB },
            set: { model.updatePreferences(memoryGB: $0) }
        )
    }

    private var diskBinding: Binding<Int> {
        Binding(
            get: { model.preferences.diskGB },
            set: { model.updatePreferences(diskGB: $0) }
        )
    }

    private var availableCloneSources: [SessionCloneSource] {
        if model.selectedSessionID == nil {
            return [.base, .primary]
        }
        return SessionCloneSource.allCases
    }
}

private enum CheckpointMode {
    case stateful
    case diskOnly
}

struct MovingGradientPlaceholder: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor, .blue, .purple, Color.accentColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .hueRotation(.degrees(animate ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                    animate.toggle()
                }
            }

            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48))
                Text("Ready to Boot")
                    .font(.headline)
                Text("Select an action to start a session")
                    .font(.subheadline)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .shadow(radius: 10)
        }
    }
}

private struct SessionRowView: View {
    let session: VMSessionSummary
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.kind == .primary ? "circle.grid.cross" : "sparkles")
                .foregroundStyle(session.kind == .primary ? Color.accentColor : .purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.subheadline)
                Text(session.kind.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
            } else if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onStart()
        }
    }
}

private struct CheckpointRowView: View {
    let checkpoint: VMCheckpoint
    let isSelected: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.circle")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.name)
                    .font(.subheadline)
                Text(checkpoint.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Restore") {
                onRestore()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}
