//
//  LockedFoldersPane.swift
//  LockGuard — Settings
//
//  Manage guarded folders: list with icon/name/toggle/remove, add via
//  NSOpenPanel, and an honest convenience-vs-security warning. Folder removal
//  is face-gated the same way app removal is.
//

import SwiftUI

struct LockedFoldersPane: View {
    @ObservedObject var lockManager: LockManager
    @State private var query = ""

    private var filtered: [LockedItem] {
        query.isEmpty ? lockManager.folders
            : lockManager.folders.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Locked Folders").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                if !lockManager.folders.isEmpty { searchField }
                Button { lockManager.presentAddFolders() } label: {
                    Label("Add Folders…", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.actionBlue))
                }.buttonStyle(.plain).focusable(false)
            }

            warning

            if lockManager.folders.isEmpty {
                emptyState
            } else {
                SettingsCard {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                        folderRow(item)
                        if i < filtered.count - 1 { Divider().overlay(Theme.hairline.opacity(0.5)) }
                    }
                }
            }
        }
    }

    private var warning: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.warning)
                Text("Folder locking hides a folder's contents behind authentication for convenience. It is not full-disk encryption — a determined user with disk access or Time Machine backups may still reach the files. Use FileVault for at-rest protection.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
            TextField("Search…", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 130)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.surface))
    }

    private func folderRow(_ item: LockedItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(item.path).font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.isLocked }, set: { lockManager.setLocked($0, for: item) }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            Button {
                // Face-required delete (hardening) — same gate as apps.
                Task {
                    if await AuthCoordinator.shared.requireAuth(reason: "Authenticate to remove \(item.name)") {
                        lockManager.remove(item)
                    }
                }
            } label: {
                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(Theme.danger)
            }.buttonStyle(.plain).focusable(false)
        }
        .padding(.vertical, 7)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.gearshape").font(.system(size: 30)).foregroundStyle(Theme.steel)
            Text("No folders locked yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Add folders to hide their contents behind authentication.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}
