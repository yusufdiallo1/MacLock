//
//  LockPopoverView.swift
//  LockGuard
//
//  The menu-bar popover. A frosted Liquid Glass panel: "Lock All Now" up top,
//  sections of guarded apps and folders in the middle, and a settings/quit
//  footer. Dark, frosted, clean — SF Symbols throughout.
//

import SwiftUI

struct LockPopoverView: View {
    @ObservedObject var lockManager: LockManager
    @ObservedObject var permissions: PermissionsManager

    var onShowSettings: () -> Void
    var onQuit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When non-.none, the popover shows the in-app app/folder picker instead
    /// of the main list — no Finder open panel.
    @State private var pickerMode: PickerMode = .none

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.75)
    }

    var body: some View {
        Group {
            if pickerMode == .none {
                mainContent
            } else {
                PickerView(lockManager: lockManager, mode: pickerMode) {
                    withAnimation(spring) { pickerMode = .none }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 520)
        .glassSurface(cornerRadius: 20)
        .onAppear { permissions.refreshAll() }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            lockAllButton
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 10)

            Divider().overlay(Theme.glassEdge)

            content

            Divider().overlay(Theme.glassEdge)
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: permissions.allGranted ? "lock.shield.fill" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(permissions.allGranted ? Theme.signal : Theme.steel)
                .frame(width: 30, height: 30)
                .glassChip(cornerRadius: 9)

            VStack(alignment: .leading, spacing: 1) {
                Text("LockGuard")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(permissions.allGranted ? Theme.signal : Theme.inkMuted)
                    .animation(spring, value: lockManager.everythingLocked)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusLine: String {
        if !permissions.allGranted { return "Finish setup to arm the guard" }
        if lockManager.isEmpty { return "Nothing guarded yet" }
        return lockManager.everythingLocked
            ? "Everything is locked"
            : "\(lockedCount) of \(lockManager.allItems.count) locked"
    }

    private var lockedCount: Int {
        lockManager.allItems.filter(\.isLocked).count
    }

    // MARK: - Lock All Now

    private var lockAllButton: some View {
        Button {
            withAnimation(spring) { lockManager.lockAll() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Lock All Now")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                if lockManager.everythingLocked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(lockManager.everythingLocked ? Theme.signal : Theme.ground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(lockAllBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)          // no macOS keyboard focus ring
        .disabled(lockManager.isEmpty)
        .opacity(lockManager.isEmpty ? 0.5 : 1)
    }

    @ViewBuilder
    private var lockAllBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if lockManager.everythingLocked {
            shape.fill(Theme.signalSoft)
                .overlay(shape.strokeBorder(Theme.signal.opacity(0.5), lineWidth: 1))
        } else {
            shape.fill(Theme.signal)
        }
    }

    // MARK: - Content: sections or empty state

    @ViewBuilder
    private var content: some View {
        if lockManager.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if !lockManager.apps.isEmpty {
                        section(title: "Apps",
                                symbol: "square.grid.2x2",
                                items: lockManager.apps)
                    }
                    if !lockManager.folders.isEmpty {
                        section(title: "Folders",
                                symbol: "folder",
                                items: lockManager.folders)
                    }
                    addRow
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func section(
        title: String,
        symbol: String,
        items: [LockedItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Spacer()
            }
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)

            ForEach(items) { item in
                LockRow(item: item) { lockManager.toggle(item) }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                    .contextMenu {
                        Button(role: .destructive) {
                            withAnimation(spring) { lockManager.remove(item) }
                        } label: {
                            Label("Stop Guarding", systemImage: "trash")
                        }
                    }
            }
        }
        .animation(spring, value: items)
    }

    /// A quiet "＋ Add" affordance under the sections.
    private var addRow: some View {
        Menu {
            Button { withAnimation(spring) { pickerMode = .apps } } label: {
                Label("Add Apps…", systemImage: "app.badge.checkmark")
            }
            Button { withAnimation(spring) { pickerMode = .folders } } label: {
                Label("Add Folders…", systemImage: "folder.badge.plus")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("Add App or Folder")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.top, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.badge.clock")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.steel)
            Text("No apps or folders guarded")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("Add the apps and folders you want LockGuard to protect when you step away.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Menu {
                Button { withAnimation(spring) { pickerMode = .apps } } label: {
                    Label("Add Apps…", systemImage: "app.badge.checkmark")
                }
                Button { withAnimation(spring) { pickerMode = .folders } } label: {
                    Label("Add Folders…", systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add Item")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassChip(cornerRadius: 10, interactive: true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            footerButton(symbol: "gearshape.fill", help: "Settings", action: onShowSettings)
            Spacer()
            Text("v1.0")
                .font(.system(size: 10))
                .foregroundStyle(Theme.inkFaint)
            Spacer()
            footerButton(symbol: "power", help: "Quit LockGuard", action: onQuit)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func footerButton(
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 30, height: 26)
                .glassChip(cornerRadius: 8, interactive: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
