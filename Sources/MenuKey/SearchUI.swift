import AppKit
import SwiftUI

enum Layout {
    static let width: CGFloat = 680
    static let headerHeight: CGFloat = 72
    static let rowHeight: CGFloat = 50
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 8
    static let maxVisibleRows = 8
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" { didSet { refilter() } }
    @Published private(set) var results: [MenuEntry] = []
    @Published var selection = 0
    @Published private(set) var loading = false
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?
    @Published var focusTick = 0

    var onExecute: ((MenuEntry) -> Void)?
    var onLayoutChange: (() -> Void)?

    private var all: [MenuEntry] = []
    private(set) var bundleID = ""

    var height: CGFloat {
        if !results.isEmpty {
            let rows = CGFloat(min(results.count, Layout.maxVisibleRows))
            return Layout.headerHeight + 1 + rows * (Layout.rowHeight + Layout.rowSpacing) + Layout.listPadding * 2
        }
        if loading || !query.isEmpty { return Layout.headerHeight + 1 + 52 }
        return Layout.headerHeight
    }

    func begin(app: NSRunningApplication) {
        appName = app.localizedName ?? "App"
        appIcon = app.icon
        bundleID = app.bundleIdentifier ?? appName
        all = []
        query = ""
        results = []
        selection = 0
        loading = true
        onLayoutChange?()
    }

    func load(_ entries: [MenuEntry]) {
        all = entries
        loading = false
        refilter()
    }

    func reset() {
        all = []
        results = []
        query = ""
        loading = false
    }

    private func refilter() {
        results = Matcher.rank(all, query: query, usage: Usage.counts(for: bundleID))
        selection = 0
        onLayoutChange?()
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
    }

    func executeSelected() {
        guard results.indices.contains(selection) else { return }
        onExecute?(results[selection])
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.results.isEmpty {
                Divider().opacity(0.4)
                list
            } else if model.loading || !model.query.isEmpty {
                Divider().opacity(0.4)
                Text(model.loading ? "Reading menus…" : "No matching menu items")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .frame(width: Layout.width, height: model.height, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .onChange(of: model.focusTick) { focused = true }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let icon = model.appIcon {
                Image(nsImage: icon).resizable().frame(width: 34, height: 34)
            }
            TextField("Search \(model.appName) menus", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 24))
                .focused($focused)
            if model.loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Layout.headerHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Layout.rowSpacing) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, entry in
                        ResultRow(entry: entry, selected: index == model.selection)
                            .id(entry.id)
                            .onTapGesture {
                                model.selection = index
                                model.executeSelected()
                            }
                    }
                }
                .padding(Layout.listPadding)
            }
            .scrollIndicators(.never)
            .onChange(of: model.selection) { _, new in
                guard model.results.indices.contains(new) else { return }
                proxy.scrollTo(model.results[new].id)
            }
            .onChange(of: model.query) {
                if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }
}

private struct ResultRow: View {
    let entry: MenuEntry
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(entry.pathString)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if !entry.shortcut.isEmpty {
                Text(entry.shortcut)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.07))
                    )
            }
        }
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .frame(height: Layout.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
