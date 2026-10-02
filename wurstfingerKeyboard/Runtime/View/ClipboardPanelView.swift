//
//  ClipboardPanelView.swift
//  Wurstfinger
//
//  Thumb-Key's clipboard history screen, shown in place of the keys.
//

import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var viewModel: KeyboardViewModel
    @ObservedObject var history: ClipboardHistory
    let palette: KeyboardPalette

    /// Row whose actions (paste, delete, pin) are showing after a long press.
    @State private var expandedItemId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !history.settings.historyEnabled {
                disabledState
            } else if history.items.isEmpty {
                message(String(localized: "Nothing copied yet"))
            } else {
                list
            }
        }
        .background(palette.surface)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            headerButton("chevron.backward", label: String(localized: "Back")) {
                viewModel.closeClipboardHistory()
            }
            Text(String(localized: "Clipboard history"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.primary)
                .frame(maxWidth: .infinity)
            headerButton("trash", label: String(localized: "Clear all")) {
                history.clearUnpinned()
            }
            headerButton("chevron.forward", label: String(localized: "Back")) {
                viewModel.closeClipboardHistory()
            }
        }
        .frame(height: 40)
        .background(palette.surfaceVariant)
    }

    private func headerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(palette.secondary)
                .frame(width: 44, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - States

    private var disabledState: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Clipboard history is turned off."))
                .font(.system(size: 14))
                .foregroundColor(palette.secondary)
            Button(String(localized: "Go to settings")) {
                viewModel.dispatchAction(.openSettings)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(palette.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(palette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var list: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(history.sortedItems) { item in
                    row(item)
                    palette.outline.opacity(0.3)
                        .frame(height: 0.5)
                }
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundColor(palette.secondary)
                }
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 15))
                    .foregroundColor(palette.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(item.date, style: .relative)
                Spacer()
                Text(String(localized: "\(item.text.count) characters"))
            }
            .font(.system(size: 11))
            .foregroundColor(palette.muted)

            if expandedItemId == item.id {
                HStack(spacing: 0) {
                    actionButton(String(localized: "Paste"), icon: "doc.on.clipboard") {
                        viewModel.pasteClipboardItem(item, closing: false)
                    }
                    actionButton(String(localized: "Delete"), icon: "trash") {
                        history.delete(item)
                    }
                    actionButton(
                        item.pinned ? String(localized: "Unpin") : String(localized: "Pin"),
                        icon: item.pinned ? "pin.slash" : "pin"
                    ) {
                        history.togglePin(item)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if expandedItemId == item.id {
                expandedItemId = nil
            } else {
                viewModel.pasteClipboardItem(item, closing: true)
            }
        }
        .onLongPressGesture {
            viewModel.feedbackTap()
            expandedItemId = expandedItemId == item.id ? nil : item.id
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.surfaceVariant))
                .padding(.horizontal, 3)
        }
        .buttonStyle(.plain)
    }
}
