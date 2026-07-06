//
//  LockRow.swift
//  LockGuard
//
//  One guarded item in the popover: its live icon, its name, and a lock toggle
//  rendered as a glass pill rather than a stock switch. Hovering lifts a soft
//  frost behind the row.
//

import SwiftUI

struct LockRow: View {
    let item: LockedItem
    let onToggle: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var spring: Animation? {
        reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(item.url.deletingLastPathComponent().path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            lockToggle
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering ? Theme.rowHover : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(spring) { isHovering = hovering }
        }
    }

    // MARK: - Icon on a small glass well

    private var icon: some View {
        Image(nsImage: item.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 26, height: 26)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.iconWell)
            )
            .saturation(item.isLocked ? 1 : 0.55)
            .opacity(item.isLocked ? 1 : 0.7)
            .animation(spring, value: item.isLocked)
    }

    // MARK: - Lock toggle as a glass pill

    private var lockToggle: some View {
        Button {
            withAnimation(spring) { onToggle() }
        } label: {
            Image(systemName: item.isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.isLocked ? Theme.signal : Theme.inkMuted)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.isLocked ? Theme.signalSoft : Theme.iconWell)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    item.isLocked ? Theme.signal.opacity(0.4) : Theme.glassEdge,
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.isLocked ? "Unlock \(item.name)" : "Lock \(item.name)")
    }
}
