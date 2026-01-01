import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingIPSWPicker = false

    var body: some View {
        NavigationSplitView {
            List {
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

                Section {
                    if model.storedIPSWs.isEmpty {
                        Text("No IPSWs yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.storedIPSWs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: entry.source == .latest ? "sparkles" : "shippingbox")
                                    .foregroundStyle(entry.source == .latest ? .purple : .accentColor)
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
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
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

                        Section("Sessions") {
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
                        }
                    } label: {
                        Label("Actions", systemImage: "play.circle.fill")
                    }
                }
            }
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
