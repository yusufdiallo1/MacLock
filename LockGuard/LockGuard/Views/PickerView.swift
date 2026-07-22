//
//  PickerView.swift
//  LockGuard
//
//  In-popover pickers that replace the Finder open panel:
//  • Apps  — a searchable list of installed apps; tap to lock.
//  • Folders — pick a location (Desktop, Downloads…), then a subfolder; tap to lock.
//

import SwiftUI

/// Which picker is showing, or none.
enum PickerMode: Equatable {
    case none
    case apps
    case folders
}

struct PickerView: View {
    @ObservedObject var lockManager: LockManager
    let mode: PickerMode
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .apps:    AppPicker(lockManager: lockManager, onBack: onBack)
            case .folders: FolderPicker(lockManager: lockManager, onBack: onBack)
            case .none:    EmptyView()
            }
        }
    }
}

// MARK: - Shared chrome

private struct PickerHeader: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 26, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.iconWell))
            }
            .buttonStyle(.plain)
            .focusable(false)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct PickRow: View {
    let icon: NSImage?
    let symbol: String?
    let name: String
    let locked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.signal)
                        .frame(width: 24, height: 24)
                }
                Text(name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: locked ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(locked ? Theme.signal : Theme.inkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovering ? Theme.rowHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

// MARK: - App picker

private struct AppPicker: View {
    @ObservedObject var lockManager: LockManager
    let onBack: () -> Void

    @State private var apps: [PickableItem] = []
    @State private var query = ""

    private var filtered: [PickableItem] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PickerHeader(title: "Choose an App to Lock", onBack: onBack)
            searchField
            Divider().overlay(Theme.glassEdge)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        PickRow(
                            icon: app.icon, symbol: nil, name: app.name,
                            locked: lockManager.isAppLocked(app)
                        ) { lockManager.lockPickedApp(app) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .frame(height: 360)
        .onAppear { if apps.isEmpty { apps = InstalledItems.installedApps() } }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkFaint)
            TextField("Search apps", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Folder picker (location → subfolders)

private struct FolderPicker: View {
    @ObservedObject var lockManager: LockManager
    let onBack: () -> Void

    @State private var locations: [FolderLocation] = []
    @State private var chosen: FolderLocation?
    @State private var subfolders: [PickableItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if let chosen {
                PickerHeader(title: chosen.name) { self.chosen = nil }
                Divider().overlay(Theme.glassEdge)
                subfolderList(chosen)
            } else {
                PickerHeader(title: "Choose a Location", onBack: onBack)
                Divider().overlay(Theme.glassEdge)
                locationList
            }
        }
        .frame(height: 360)
        .onAppear { if locations.isEmpty { locations = InstalledItems.folderLocations() } }
    }

    private var locationList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(locations) { loc in
                    PickRow(icon: nil, symbol: loc.symbol, name: loc.name, locked: false) {
                        chosen = loc
                        subfolders = InstalledItems.subfolders(of: loc)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func subfolderList(_ loc: FolderLocation) -> some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // Let the user lock the whole location, too.
                PickRow(
                    icon: nil, symbol: "folder.fill.badge.plus",
                    name: "Lock “\(loc.name)” itself",
                    locked: lockManager.isFolderLocked(PickableItem(path: loc.path, name: loc.name, bundleID: nil))
                ) {
                    lockManager.lockPickedFolder(PickableItem(path: loc.path, name: loc.name, bundleID: nil))
                }
                if subfolders.isEmpty {
                    Text("No subfolders here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.inkFaint)
                        .padding(.vertical, 12)
                } else {
                    ForEach(subfolders) { folder in
                        PickRow(
                            icon: folder.icon, symbol: nil, name: folder.name,
                            locked: lockManager.isFolderLocked(folder)
                        ) { lockManager.lockPickedFolder(folder) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}
