//
//  KeyboardGridView.swift
//  Wurstfinger
//
//  Generic renderer for any GridArrangement + key pool.
//

import SwiftUI

/// A placement resolved to its grid position.
struct GridCell: Equatable {
    let placement: KeyPlacement
    let row: Int
    let column: Int
}

/// Generic grid renderer that lays out a `GridArrangement`. Keys can span
/// several columns (e.g. space) and several rows (e.g. the landscape return
/// key); keys fill their cells without gaps.
struct KeyboardGridView: View {
    let arrangement: GridArrangement
    let keys: [String: KeyConfig]
    let look: KeyLook
    /// Height of one key row, in points.
    let keyHeight: CGFloat
    let makeGestureConfig: (KeyConfig, CGFloat) -> KeyGestureConfig
    let onTouchDown: () -> Void
    let onEvent: (KeyConfig, KeyGestureEvent) -> KeyAction?

    var body: some View {
        KeyGridLayout(columns: arrangement.columns, rows: arrangement.rows.count, rowHeight: keyHeight) {
            ForEach(Self.cells(for: arrangement), id: \.placement.keyId) { cell in
                cellContent(for: cell.placement)
                    .layoutValue(key: GridCellKey.self, value: cell)
            }
        }
    }

    @ViewBuilder
    private func cellContent(for placement: KeyPlacement) -> some View {
        if let key = keys[placement.keyId] {
            KeyView(
                key: key,
                look: look,
                height: keyHeight * CGFloat(placement.heightMultiplier),
                columnSpan: CGFloat(placement.widthMultiplier),
                rowSpan: CGFloat(placement.heightMultiplier),
                makeGestureConfig: makeGestureConfig,
                onTouchDown: onTouchDown,
                onEvent: onEvent
            )
            .id(placement.keyId)
        } else {
            Color.clear
        }
    }

    // MARK: - Grid Positions

    /// Resolves each placement's row and column. A key taller than one row
    /// occupies its columns in the rows below, which later placements skip.
    static func cells(for arrangement: GridArrangement) -> [GridCell] {
        var occupied: [Int: Set<Int>] = [:]
        var cells: [GridCell] = []
        for (rowIndex, row) in arrangement.rows.enumerated() {
            var column = 0
            for placement in row {
                while occupied[rowIndex, default: []].contains(column) {
                    column += 1
                }
                cells.append(GridCell(placement: placement, row: rowIndex, column: column))
                for extraRow in 1 ..< max(placement.heightMultiplier, 1) {
                    for spanned in column ..< column + placement.widthMultiplier {
                        occupied[rowIndex + extraRow, default: []].insert(spanned)
                    }
                }
                column += placement.widthMultiplier
            }
        }
        return cells
    }

    // MARK: - Span Inspection (Test Hooks)

    /// Returns the `(rows, columns)` grid span for a placement. Pure function
    /// so the spanning behavior can be unit tested without introspecting the
    /// rendered SwiftUI tree.
    static func gridCellSpan(for placement: KeyPlacement) -> (rows: Int, columns: Int) {
        (placement.heightMultiplier, placement.widthMultiplier)
    }
}

private struct GridCellKey: LayoutValueKey {
    static let defaultValue = GridCell(placement: KeyPlacement(keyId: ""), row: 0, column: 0)
}

/// Places each key at its cell, sized by its column and row span.
private struct KeyGridLayout: Layout {
    let columns: Int
    let rows: Int
    let rowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        CGSize(
            width: proposal.width ?? CGFloat(columns) * rowHeight,
            height: CGFloat(rows) * rowHeight
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let columnWidth = bounds.width / CGFloat(max(columns, 1))
        for subview in subviews {
            let cell = subview[GridCellKey.self]
            let size = CGSize(
                width: columnWidth * CGFloat(cell.placement.widthMultiplier),
                height: rowHeight * CGFloat(cell.placement.heightMultiplier)
            )
            subview.place(
                at: CGPoint(x: bounds.minX + columnWidth * CGFloat(cell.column), y: bounds.minY + rowHeight * CGFloat(cell.row)),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
        }
    }
}
