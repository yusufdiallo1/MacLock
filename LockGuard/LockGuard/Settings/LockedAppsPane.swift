//
//  LockedAppsPane.swift
//  LockGuard — Settings
//
//  The Locked Apps pane and its "Add Apps to Lock" installed-apps picker.
//  Lifted verbatim from the original SettingsView; behavior unchanged.
//

import SwiftUI

struct LockedAppsPane: View {
    @ObservedObject var lockManager: LockManager
    @State private var showPicker = false
    @State private var query = ""

    private var filtered: [LockedItem] {
        query.isEmpty ? lockManager.apps
            : lockManager.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Locked Apps").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                searchField
                Button { showPicker = true } label: {
                    Label("Add Apps…", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Theme.actionBlue))
                }.buttonStyle(.plain).focusable(false)
            }

            if lockManager.apps.isEmpty {
                emptyState
            } else {
                Text("Click an app to customize its session timer")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.inkFaint)
                SettingsCard {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { i, item in
                        appRow(item)
                        if i < filtered.count - 1 { Divider().overlay(Theme.hairline.opacity(0.5)) }
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            InstalledAppsPicker(lockManager: lockManager) { showPicker = false }
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

    private func appRow(_ item: LockedItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: item.icon).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.ink)
                Text(item.bundleID ?? item.path).font(.system(size: 10.5)).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { item.isLocked }, set: { lockManager.setLocked($0, for: item) }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
            Button {
                // Face-required delete (hardening).
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
            Image(systemName: "lock.square").font(.system(size: 30)).foregroundStyle(Theme.steel)
            Text("No apps locked yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink)
            Text("Add apps to require authentication when they're opened.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.inkMuted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

/// Installed-apps picker — the reference's "Add Apps to Lock" list.
struct InstalledAppsPicker: View {
    @ObservedObject var lockManager: LockManager
    let onDone: () -> Void
    @State private var apps: [PickableItem] = []
    @State private var query = ""
    private var filtered: [PickableItem] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDone) { Label("Done", systemImage: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).focusable(false).foregroundStyle(Theme.actionBlue)
                Text("Add Apps to Lock").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.inkFaint)
                    TextField("Search…", text: $query).textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 120)
                }.padding(.horizontal, 10).padding(.vertical, 6).background(Capsule().fill(Theme.surface))
            }.padding(16)
            Divider().overlay(Theme.hairline)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { app in
                        HStack(spacing: 11) {
                            Image(nsImage: app.icon).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name).font(.system(size: 13)).foregroundStyle(Theme.ink)
                                Text(app.bundleID ?? "").font(.system(size: 10)).foregroundStyle(Theme.inkFaint)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { lockManager.isAppLocked(app) },
                                set: { on in if on { lockManager.lockPickedApp(app) } }
                            )).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }.padding(8)
            }
        }
        .frame(width: 480, height: 500).background(Theme.ground)
        .onAppear { if apps.isEmpty { apps = InstalledItems.installedApps() } }
    }
}
