import AppKit
import SwiftUI

enum Layout {
    static let width: CGFloat = 680
    static let headerHeight: CGFloat = 72
    static let chipsHeight: CGFloat = 46
    static let rowHeight: CGFloat = 50
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 8
    static let thinkingHeight: CGFloat = 38
    static let maxVisibleRows = 8
}

enum Scope: Int, CaseIterable, Identifiable {
    case all, menus, windows, menuBar, files
    var id: Int { rawValue }
    var label: String { ["All", "Menus", "Windows", "Menu Bar", "Files"][rawValue] }
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" { didSet { if query != oldValue { queryChanged() } } }
    @Published var scope: Scope = .all { didSet { if scope != oldValue { scopeChanged() } } }
    @Published private(set) var results: [SearchItem] = []
    @Published var selection = 0 { didSet { onSelectionChange?() } }
    /// True once the user picks a row with the arrow keys. Only then do late
    /// results (files, windows) keep the selection where it is; otherwise the
    /// top result stays selected as results arrive.
    private var userChoseSelection = false
    @Published private(set) var loading = false
    @Published private(set) var thinking = false
    @Published private(set) var appName = ""
    @Published private(set) var appIcon: NSImage?
    @Published var focusTick = 0

    private(set) var bundleID = ""
    /// Set by the "z " prefix: zoxide-style folder jumping, no files.
    @Published private(set) var foldersOnly = false
    private(set) var targetIsTerminal = false

    var onExecute: ((SearchItem, Bool) -> Void)?
    var onLayoutChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    private var menus: [SearchItem] = []
    private var windows: [SearchItem] = []
    private var extras: [SearchItem] = []
    private var folders: [SearchItem] = []
    private var suggestions: [SearchItem] = []
    private var suggestionsQuery = ""
    private var folderToken = 0
    private var aiToken = 0

    var selected: SearchItem? { results.indices.contains(selection) ? results[selection] : nil }
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var height: CGFloat {
        let top = Layout.headerHeight + Layout.chipsHeight
        let thinkingRow = thinking ? Layout.thinkingHeight : 0
        if !results.isEmpty {
            let rows = CGFloat(min(results.count, Layout.maxVisibleRows))
            return top + 1 + thinkingRow + rows * (Layout.rowHeight + Layout.rowSpacing) + Layout.listPadding * 2
        }
        if thinking { return top + 1 + thinkingRow + Layout.listPadding * 2 }
        return top + 1 + 52
    }

    var emptyMessage: String {
        if loading { return "Reading menus…" }
        switch scope {
        case .files where trimmedQuery.isEmpty: return foldersOnly ? "Type part of a folder's name" : "Type part of a file or folder name"
        case .files: return foldersOnly ? "No matching folders" : "No matching files or folders"
        case .windows: return trimmedQuery.isEmpty ? "No open windows" : "No matching windows"
        case .menuBar: return trimmedQuery.isEmpty ? "No menu bar icons found" : "No matching menu bar icons"
        default: return trimmedQuery.isEmpty ? "No menu items" : "No matches"
        }
    }

    // MARK: Lifecycle

    func begin(app: NSRunningApplication) {
        appName = app.localizedName ?? "App"
        appIcon = app.icon
        bundleID = app.bundleIdentifier ?? appName
        targetIsTerminal = Terminals.isTerminal(app.bundleIdentifier)
        menus = []; windows = []; extras = []; folders = []; suggestions = []
        suggestionsQuery = ""
        thinking = false
        aiToken += 1
        folderToken += 1
        query = ""
        scope = .all
        foldersOnly = false
        results = []
        selection = 0
        loading = true
        onLayoutChange?()
    }

    func setMenus(_ items: [SearchItem]) { menus = items; loading = false; refilter() }
    func setWindows(_ items: [SearchItem]) { windows = items; refilter(keepSelection: true) }
    func setExtras(_ items: [SearchItem]) { extras = items; refilter(keepSelection: true) }

    func reset() {
        menus = []; windows = []; extras = []; folders = []; suggestions = []
        results = []
        query = ""
        loading = false
        thinking = false
        aiToken += 1
        folderToken += 1
    }

    // MARK: Filtering

    private func queryChanged() {
        userChoseSelection = false
        if query.hasPrefix("z ") {
            // zoxide muscle memory: "z proj" jumps straight into folder search.
            // Deferred so the text field sees the change.
            foldersOnly = true
            scope = .files
            DispatchQueue.main.async { [weak self] in
                guard let self, self.query.hasPrefix("z ") else { return }
                self.query = String(self.query.dropFirst(2))
            }
            return
        }
        aiToken += 1
        if thinking { thinking = false }
        if trimmedQuery != suggestionsQuery { suggestions = [] }
        refilter()
        scheduleFolderSearch()
    }

    private func scopeChanged() {
        userChoseSelection = false
        if scope != .files { foldersOnly = false }
        refilter()
        scheduleFolderSearch()
        focusTick += 1
    }

    func cycleScope(_ delta: Int) {
        let all = Scope.allCases
        scope = all[(scope.rawValue + delta + all.count) % all.count]
    }

    private func refilter(keepSelection: Bool = false) {
        let previous = selected?.id
        let q = trimmedQuery
        var ranked: [Matcher.Scored]

        switch scope {
        case .all:
            if q.isEmpty {
                ranked = Matcher.rank(menus, query: "")
            } else {
                let topFolders = Matcher.rank(folders, query: q).prefix(3).map(\.item)
                ranked = Matcher.rank(menus + windows + extras + topFolders, query: q, kindOffsets: true)
            }
        case .menus: ranked = Matcher.rank(menus, query: q)
        case .windows: ranked = Matcher.rank(windows, query: q)
        case .menuBar: ranked = Matcher.rank(extras, query: q)
        case .files:
            // zoxide/Spotlight order, with items you've opened through JumpKey first.
            let f = Frecency.shared
            ranked = folders
                .map { Matcher.Scored(item: $0, score: Int(f.score($0.frecencyKey) * 100) - $0.order, strong: true) }
                .sorted { $0.score > $1.score }
            if !FolderSource.askedForFolderAccess {
                ranked.insert(Matcher.Scored(item: FolderSource.accessRow, score: .max, strong: true), at: 0)
            }
        }

        let hasStrongMenu = ranked.contains { $0.strong && $0.item.kind == .menu }
        var items = ranked.map(\.item)
        if !suggestions.isEmpty, scope == .all || scope == .menus {
            let ids = Set(suggestions.map(\.id))
            items = suggestions + items.filter { !ids.contains($0.id) }
        }
        results = items

        if keepSelection, userChoseSelection, let previous, let idx = results.firstIndex(where: { $0.id == previous }) {
            selection = idx
        } else {
            selection = 0
        }
        onLayoutChange?()
        maybeAskAssistant(hasStrongMatch: hasStrongMenu)
    }

    // MARK: Folders

    private func scheduleFolderSearch() {
        let q = trimmedQuery
        guard scope == .files || (scope == .all && q.count >= 2) else {
            if !folders.isEmpty { folders = []; refilter(keepSelection: true) }
            return
        }
        folderToken += 1
        let token = folderToken
        let tokens = q.split(separator: " ").map(String.init)
        let limit = scope == .files ? 40 : 6
        let foldersOnly = self.foldersOnly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, token == self.folderToken else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let items = FolderSource.search(tokens: tokens, foldersOnly: foldersOnly, limit: limit)
                DispatchQueue.main.async {
                    guard token == self.folderToken else { return }
                    self.folders = items
                    self.refilter(keepSelection: true)
                }
            }
        }
    }

    // MARK: Plain-English fallback

    private func maybeAskAssistant(hasStrongMatch: Bool) {
        let q = trimmedQuery
        guard Settings.plainEnglish, scope == .all || scope == .menus, !loading, !menus.isEmpty,
              q.count >= 6, q.contains(" "), !hasStrongMatch, q != suggestionsQuery, !thinking,
              Assistant.isAvailable else { return }
        aiToken += 1
        let token = aiToken
        let app = appName
        let menuTitles = MenuScanner.topLevelTitles(menus)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, token == self.aiToken else { return }
            self.thinking = true
            self.onLayoutChange?()
            let commands = await Assistant.guessCommands(for: q, app: app, menus: menuTitles)
            guard token == self.aiToken else { return }
            self.thinking = false
            self.suggestionsQuery = q
            self.suggestions = Matcher.phraseMatches(commands, in: self.menus)
            self.refilter()
        }
    }

    // MARK: Actions

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + delta + results.count) % results.count
        userChoseSelection = true
    }

    func executeSelected(alternate: Bool = false) {
        guard let item = selected else { return }
        onExecute?(item, alternate)
    }

    func hint(for kind: ItemKind) -> String {
        switch kind {
        case .folder: return targetIsTerminal ? "⌘↩ Finder" : "⌘↩ \(Terminals.selectedName)"
        case .file: return "⌘↩ Show in Finder"
        default: return ""
        }
    }
}

// MARK: - Views

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            chips
            Divider().opacity(0.4)
            if model.thinking { thinkingRow }
            if !model.results.isEmpty {
                list
            } else if !model.thinking {
                Text(model.emptyMessage)
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
            TextField(placeholder, text: $model.query)
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

    private var placeholder: String {
        switch model.scope {
        case .all: return "Search \(model.appName)"
        case .menus: return "Search \(model.appName) menus"
        case .windows: return "Search open windows"
        case .menuBar: return "Search menu bar icons"
        case .files: return model.foldersOnly ? "Jump to a folder" : "Search files and folders"
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(Scope.allCases) { scope in
                let on = model.scope == scope
                Text(scope.label)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.06)))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .contentShape(Capsule())
                    .onTapGesture { model.scope = scope }
            }
            Spacer()
            Text("⇥")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: Layout.chipsHeight, alignment: .top)
    }

    private var thinkingRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            Text("Looking for “\(model.trimmedQuery)” with Apple Intelligence…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            ProgressView().controlSize(.mini)
        }
        .padding(.horizontal, 20)
        .frame(height: Layout.thinkingHeight)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Layout.rowSpacing) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        ResultRow(item: item, query: model.trimmedQuery, selected: index == model.selection,
                                  hint: model.hint(for: item.kind))
                            .id(item.id)
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
    let item: SearchItem
    let query: String
    let selected: Bool
    let hint: String

    var body: some View {
        HStack(spacing: 12) {
            leading
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(titleText)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    if item.checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(selected ? Color.white : Color.accentColor)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            trailing
        }
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .frame(height: Layout.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leading: some View {
        if item.suggested {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
        } else if let icon = item.icon {
            Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "filemenu.and.selection")
                .font(.system(size: 14))
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.tertiary))
        }
    }

    @ViewBuilder private var trailing: some View {
        if (item.kind == .folder || item.kind == .file) && selected {
            Text(hint)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        } else if !item.shortcut.isEmpty {
            Text(item.shortcut)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(selected ? Color.white.opacity(0.2) : Color.primary.opacity(0.07)))
        }
    }

    private var subtitle: String {
        item.suggested ? "Suggested · \(item.subtitle)" : item.subtitle
    }

    private var titleText: AttributedString {
        var s = AttributedString(item.title)
        guard !item.suggested, !query.isEmpty else { return s }
        let hits = Matcher.highlights(query: query, title: item.title)
        guard !hits.isEmpty else { return s }
        var idx = s.startIndex
        var i = 0
        while idx < s.endIndex {
            let next = s.characters.index(after: idx)
            if hits.contains(i) {
                s[idx..<next].font = .system(size: 15, weight: .heavy)
                if !selected { s[idx..<next].foregroundColor = .accentColor }
            }
            idx = next
            i += 1
        }
        return s
    }
}
