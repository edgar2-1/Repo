import SwiftUI
import RestockKit

struct PantryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var search = ""
    @State private var sort: Sort = .aisle
    @State private var open: IDBox?

    enum Sort: String, CaseIterable, Identifiable {
        case aisle = "Aisles", due = "Next due", name = "A–Z", store = "Store"
        var id: String { rawValue }
    }

    private struct Shelf: Identifiable { let title: String; let items: [Item]; var id: String { title } }

    var body: some View {
        NavigationStack {
            List {
                if model.data.items.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "cabinet", description: Text("Items you add or scan show up here."))
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(shelves) { shelf in
                    Section {
                        ForEach(shelf.items) { item in
                            ItemRow(item: item, mode: .pantry) { open = IDBox(id: item.id) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { model.toggleList(item.id) } label: {
                                        Label(item.onList ? "Remove from list" : "Add to list", systemImage: item.onList ? "minus.circle" : "plus.circle")
                                    }
                                    .tint(.accentColor)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { model.delete(item.id) } label: { Label("Delete", systemImage: "trash") }
                                    Button { model.snooze(item.id) } label: { Label("Snooze", systemImage: "clock") }.tint(.gray)
                                }
                        }
                    } header: {
                        if !shelf.title.isEmpty { HStack { Text(shelf.title); Spacer(); Text("\(shelf.items.count)") } }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search pantry")
            .navigationTitle("Pantry")
            .toolbar {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
            .sheet(item: $open) { ItemDetailView(itemID: $0.id) }
        }
    }

    private var filtered: [Item] {
        let q = Words.norm(search)
        guard !q.isEmpty else { return model.data.items }
        return model.data.items.filter { item in
            [item.name, item.category, item.notes ?? ""].contains { Words.norm($0).contains(q) } || item.aliases.contains { Words.norm($0).contains(q) }
        }
    }

    private func byDue(_ a: Item, _ b: Item) -> Bool {
        let order: [StockStatus: Int] = [.overdue: 0, .soon: 1, .ok: 2, .unknown: 3]
        let pa = model.data.prediction(a, today: model.today), pb = model.data.prediction(b, today: model.today)
        if pa.status != pb.status { return order[pa.status]! < order[pb.status]! }
        if (pa.daysLeft ?? 999) != (pb.daysLeft ?? 999) { return (pa.daysLeft ?? 999) < (pb.daysLeft ?? 999) }
        return a.name < b.name
    }

    private var shelves: [Shelf] {
        let items = filtered
        switch sort {
        case .aisle:
            let by = Dictionary(grouping: items, by: \.category)
            let keys = Categories.all.filter { by[$0] != nil } + by.keys.filter { !Categories.all.contains($0) }.sorted()
            return keys.map { Shelf(title: $0, items: by[$0]!.sorted(by: byDue)) }
        case .store:
            let by = Dictionary(grouping: items) { AppData.usualStore($0) ?? "No store yet" }
            return by.keys.sorted { ($0 == "No store yet" ? 1 : 0, $0) < ($1 == "No store yet" ? 1 : 0, $1) }.map { Shelf(title: $0, items: by[$0]!.sorted(by: byDue)) }
        case .due:
            return items.isEmpty ? [] : [Shelf(title: "", items: items.sorted(by: byDue))]
        case .name:
            return items.isEmpty ? [] : [Shelf(title: "", items: items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })]
        }
    }
}
