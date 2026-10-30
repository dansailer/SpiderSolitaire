#if canImport(SwiftUI)
import SpiderBoard
import SwiftUI

/// The help window: a sidebar of sections (Rules, Scoring, Tips, Achievements, Keyboard Shortcuts)
/// and the selected section's text. All content comes from `HelpContent` in SpiderBoard.
struct HelpView: View {

    @State private var selection: HelpSection.ID? = HelpSection.ID.rules

    var body: some View {
        NavigationSplitView {
            List(HelpContent.sections, selection: $selection) { (section: HelpSection) in
                // No explicit .tag: List(data, selection:) tags each row with its `id`, which
                // matches the optional selection.
                Label(loc(section.title), systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            let section: HelpSection = HelpContent.section(selection ?? HelpSection.ID.rules)
            ScrollView {
                HelpSectionView(section: section)
                    .padding(EdgeInsets(top: 18, leading: 22, bottom: 24, trailing: 22))
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
            }
            .id(section.id)
        }
        .frame(minWidth: 540, idealWidth: 600, minHeight: 420, idealHeight: 640)
    }
}

struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: HorizontalAlignment.leading, spacing: 10) {
            Text(loc(section.title))
                .font(Font.title2.weight(Font.Weight.semibold))
            ForEach(Array(section.blocks.enumerated()), id: \.offset) { (item: (offset: Int, element: HelpBlock)) in
                HelpBlockView(block: item.element)
            }
        }
        .textSelection(.enabled)
    }
}

struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .heading(let text):
            Text(loc(text))
                .font(Font.headline)
                .padding(EdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0))
        case .paragraph(let text):
            Text(loc(text))
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: HorizontalAlignment.leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    HStack(alignment: VerticalAlignment.firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(loc(item.element))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let header, let rows):
            HelpTableView(header: header, rows: rows)
        }
    }
}

/// Two columns in a light box, like a System Settings list.
struct HelpTableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: Alignment.leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { (item: (offset: Int, element: String)) in
                    Text(loc(item.element))
                        .font(Font.caption.weight(Font.Weight.semibold))
                        .foregroundColor(Color.secondary)
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { (row: (offset: Int, element: [String])) in
                GridRow(alignment: VerticalAlignment.firstTextBaseline) {
                    ForEach(Array(row.element.enumerated()), id: \.offset) { (cell: (offset: Int, element: String)) in
                        Text(loc(cell.element))
                            .font(cell.offset == 0 ? Font.body.weight(Font.Weight.medium) : Font.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        )
    }
}
#endif
