import AppKit
import BarnataCore
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.tab {
            case .general: GeneralTab(model: model)
            case .configs: ConfigsTab(model: model)
            }
        }
        .frame(
            minWidth: SettingsWindowController.minimumContentSize.width,
            maxWidth: .infinity,
            minHeight: SettingsWindowController.minimumContentSize.height,
            maxHeight: .infinity
        )
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: SettingsModel
    @State private var isConfirmingUninstall = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Permissions") {
                    SetupRow(
                        title: "Background daemon",
                        isDone: model.daemonApproved,
                        actionTitle: "Approve…",
                        action: model.approveDaemon
                    )
                    SetupRow(
                        title: model.accessibilityPaneName,
                        isDone: model.hasAccessibility,
                        actionTitle: "Grant…",
                        action: model.grantAccessibility
                    )
                    if let driver = model.driver {
                        SetupRow(
                            title: "Karabiner driver",
                            isDone: driver.installed && driver.activated,
                            actionTitle: driver.installed ? "Activate…" : "Install…",
                            action: driver.installed ? model.activateDriver : model.installDriver
                        )
                    }
                }

                Section("Behavior") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    Toggle("Show in Dock", isOn: Binding(
                        get: { model.showDockIcon },
                        set: { model.setShowDockIcon($0) }
                    ))
                }
                .toggleStyle(.switch)
            }
            .formStyle(.grouped)

            HStack {
                Button("Uninstall Barnata", role: .destructive) { isConfirmingUninstall = true }
                    .disabled(model.isUninstalling)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $isConfirmingUninstall) {
            UninstallSheet(model: model, isPresented: $isConfirmingUninstall)
        }
    }
}

private struct SetupRow: View {
    let title: String
    let isDone: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Image(systemName: isDone ? "checkmark.circle.fill" : IconCatalog.warningSymbol)
                    .foregroundStyle(isDone ? Color.green : Color.orange)
                if !isDone {
                    Button(actionTitle, action: action)
                }
            }
        }
    }
}

private struct UninstallSheet: View {
    @ObservedObject var model: SettingsModel
    @Binding var isPresented: Bool

    @State private var confirmation = ""

    private var word: String { SettingsModel.uninstallConfirmationWord }
    private var canUninstall: Bool { confirmation == word && !model.isUninstalling }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Uninstall Barnata", systemImage: IconCatalog.warningSymbol)
                .font(.headline)
                .foregroundStyle(.orange)

            Text("This will stop kanata, remove the background daemon, and delete Barnata. Any kanata config files you added will not be deleted.")
                .fixedSize(horizontal: false, vertical: true)

            Text("Type \(word) to confirm.")
            TextField(word, text: $confirmation)
                .onSubmit { if canUninstall { uninstall() } }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Uninstall", role: .destructive) { uninstall() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canUninstall)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func uninstall() {
        isPresented = false
        model.uninstall()
    }
}

// MARK: - Configs

private struct ConfigsTab: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingDelete: ConfigEntry?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .confirmationDialog(
            "Remove \(confirmingDelete?.name ?? "")?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { entry in
            Button("Remove", role: .destructive) { model.delete(entry) }
        } message: { _ in
            Text("The file itself stays where it is.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $model.selection) {
                ForEach(model.entries) { entry in
                    ConfigRow(entry: entry, isActive: entry.name == model.activePresetName)
                        .tag(entry.id)
                }
            }
            .listStyle(.bordered)
            .onChange(of: model.selection) { model.selectionDidChange() }

            ControlGroup {
                Button { model.addConfigFile() } label: { Image(systemName: "plus") }
                    .help("Add a kanata config file")
                Button { confirmingDelete = model.selectedEntry } label: { Image(systemName: "minus") }
                    .disabled(model.selectedEntry == nil)
                    .help("Remove the selected config")
            }
            .controlGroupStyle(.navigation)
            .frame(width: 68)
        }
        .padding(14)
        .frame(width: 214)
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = model.selectedEntry {
            ConfigDetail(model: model, entry: entry)
        } else {
            VStack(spacing: 10) {
                Text("No config selected").foregroundStyle(.secondary)
                Button("Add Config File…") { model.addConfigFile() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ConfigRow: View {
    let entry: ConfigEntry
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).lineLimit(1)
                Text((entry.path as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .help("Running now")
            }
            if entry.isMissing || entry.hasInvalidIcons {
                Image(systemName: IconCatalog.warningSymbol)
                    .foregroundStyle(.orange)
                    .help(entry.isMissing ? "This file is missing" : "Some icons are not available")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ConfigDetail: View {
    @ObservedObject var model: SettingsModel
    let entry: ConfigEntry

    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draftName)
                    .focused($isNameFocused)
                    .onSubmit(commitName)
                LabeledContent("File") {
                    HStack(spacing: 8) {
                        if entry.isMissing {
                            Image(systemName: IconCatalog.warningSymbol)
                                .foregroundStyle(.orange)
                                .help("This file no longer exists")
                        }
                        Text((entry.path as NSString).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show in Finder") { model.reveal(entry.path) }
                    }
                }
            }

            Section("Layers") {
                if model.layers.isEmpty {
                    Text("No layers in this file.").foregroundStyle(.secondary)
                } else {
                    LayerIconRow(
                        title: "All other layers",
                        symbol: entry.layerIcons[Preset.layerIconFallbackKey],
                        onSelect: { model.setIcon($0, for: Preset.layerIconFallbackKey, in: entry) }
                    )
                    ForEach(model.layers, id: \.self) { layer in
                        LayerIconRow(
                            title: layer,
                            symbol: entry.layerIcons[layer],
                            onSelect: { model.setIcon($0, for: layer, in: entry) }
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftName = entry.name }
        .onChange(of: entry.id) { draftName = entry.name }
        // Typing then clicking away commits, the way a Finder rename does
        .onChange(of: isNameFocused) { if !isNameFocused { commitName() } }
    }

    private func commitName() {
        model.rename(entry, to: draftName)
        draftName = model.selectedEntry?.name ?? entry.name
    }
}

// MARK: - Layer icons

private struct LayerIconRow: View {
    let title: String
    let symbol: String?
    let onSelect: (String?) -> Void

    @State private var isPickerOpen = false

    private var isInvalid: Bool { symbol.map { !LayerSymbol.isAvailable($0) } ?? false }

    var body: some View {
        LabeledContent(title) {
            Button { isPickerOpen = true } label: {
                HStack(spacing: 4) {
                    preview
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .help(isInvalid ? "\(symbol ?? "") is not a symbol this Mac can draw" : "Choose an icon")
            .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
                IconPicker(selected: symbol) { choice in
                    isPickerOpen = false
                    onSelect(choice)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isInvalid {
            Image(systemName: IconCatalog.warningSymbol).foregroundStyle(.orange)
        } else if let symbol {
            Image(systemName: symbol)
        } else {
            Text("None").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct IconPicker: View {
    let selected: String?
    let onSelect: (String?) -> Void

    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Any symbol this Mac can draw is a valid icon, so a typed name gets its own row
    private var typedSymbol: String? {
        guard !trimmedQuery.isEmpty, !IconCatalog.isCurated(trimmedQuery),
              LayerSymbol.isAvailable(trimmedQuery)
        else { return nil }
        return trimmedQuery
    }

    private var groups: [IconCatalog.Group] {
        let needle = trimmedQuery.lowercased()
        return IconCatalog.groups.compactMap { group in
            let symbols = group.symbols.filter {
                (needle.isEmpty || $0.contains(needle)) && LayerSymbol.isAvailable($0)
            }
            return symbols.isEmpty ? nil : IconCatalog.Group(name: group.name, symbols: symbols)
        }
    }

    private var isEmpty: Bool { groups.isEmpty && typedSymbol == nil }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                Button("None") { onSelect(nil) }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let typedSymbol {
                        section(named: "Typed name", symbols: [typedSymbol])
                    }
                    ForEach(groups) { group in
                        section(named: group.name, symbols: group.symbols)
                    }
                }
            }

            if isEmpty {
                Text(trimmedQuery.isEmpty ? "No icons" : "No SF Symbol named \u{201C}\(trimmedQuery)\u{201D}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(width: 330, height: 360)
    }

    private func section(named name: String, symbols: [String]) -> some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 9), spacing: 4) {
                ForEach(symbols, id: \.self) { symbol in
                    IconCell(symbol: symbol, isSelected: symbol == selected) { onSelect(symbol) }
                }
            }
        } header: {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        }
    }
}

private struct IconCell: View {
    let symbol: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(systemName: symbol)
                .frame(width: 30, height: 26)
                .background(isSelected ? Color.accentColor.opacity(0.25) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol)
    }
}
