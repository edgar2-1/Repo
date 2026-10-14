import SwiftUI
import RestockKit

struct ShoppingListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newItems = ""
    @State private var open: IDBox?
    @State private var finishing = false
    @FocusState private var addFocused: Bool

    private struct StoreGroup: Identifiable { let store: String; let items: [Item]; var id: String { store } }

    var body: some View {
        let s = model.data.listSections(today: model.today)
        let nowStores = Set(s.now.compactMap(AppData.usualStore))
        let extras = s.soon.filter { AppData.usualStore($0).map(nowStores.contains) ?? false }
        let comingUp = s.now.isEmpty ? s.soon : s.soon.filter { !extras.contains($0) }
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add items, e.g. 2 oat milk, eggs", text: $newItems)
                            .focused($addFocused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .buttonStyle(.borderless)
                            .disabled(newItems.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions) { item in
                                    Button(item.name) { complete(with: item.name) }
                                        .buttonStyle(.bordered).controlSize(.small)
                                }
                            }
                        }
                    }
                } footer: {
                    if !s.now.isEmpty { Text(summary(s.now)) }
                }

                if model.data.items.isEmpty {
                    ContentUnavailableView {
                        Label("Never run out again", systemImage: "cart")
                    } description: {
                        Text("Restock learns how often you buy things and puts them here before you run out. Scan a receipt or add a few items above.")
                    } actions: {
                        Button("See an example") { model.loadSample() }.buttonStyle(.borderedProminent)
                    }
                } else if s.now.isEmpty && s.soon.isEmpty && s.cart.isEmpty {
                    ContentUnavailableView("All stocked", systemImage: "checkmark.seal", description: Text("Items show up here a few days before they're predicted to run out."))
                }

                if model.settings.groupByStore {
                    ForEach(groups(s.now)) { g in
                        Section {
                            rows(g.items, .list)
                            if !g.store.isEmpty { suggestRow(store: g.store, items: extras.filter { AppData.usualStore($0) == g.store }) }
                        } header: {
                            HStack { Text(g.store.isEmpty ? "Any store" : g.store); Spacer(); Text(subtotal(g.items)) }
                        }
                    }
                } else if !s.now.isEmpty {
                    Section("Buy now") {
                        rows(s.now, .list)
                        ForEach(nowStores.sorted(), id: \.self) { store in
                            suggestRow(store: store, items: extras.filter { AppData.usualStore($0) == store })
                        }
                    }
                }

                if !comingUp.isEmpty {
                    Section {
                        rows(comingUp, .list)
                    } header: {
                        HStack { Text("Coming up"); Spacer(); Text("next \(model.settings.soonDays) days") }
                    }
                }

                if !s.cart.isEmpty {
                    Section {
                        rows(s.cart, .cart)
                    } header: {
                        HStack { Text("In cart"); Spacer(); Text(subtotal(s.cart)) }
                    }
                }
            }
            .navigationTitle("Shopping")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.updateSettings { $0.groupByStore.toggle() }
                    } label: {
                        Label("Group by store", systemImage: model.settings.groupByStore ? "storefront.fill" : "storefront")
                    }
                    ShareLink(item: model.data.listText(today: model.today)) {
                        Label("Share list", systemImage: "square.and.arrow.up")
                    }
                    .disabled(s.now.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !s.cart.isEmpty {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(s.cart.count) in cart").font(.headline)
                            let t = subtotal(s.cart)
                            if !t.isEmpty { Text(t).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Finish trip") { finishing = true }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(.bar)
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.snappy, value: s.cart.map(\.id))
            .sheet(item: $open) { ItemDetailView(itemID: $0.id) }
            .sheet(isPresented: $finishing) { FinishTripView() }
        }
    }

    @ViewBuilder
    private func rows(_ items: [Item], _ mode: ItemRow.Mode) -> some View {
        ForEach(items) { item in
            ItemRow(item: item, mode: mode) { open = IDBox(id: item.id) }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { model.toggleCart(item.id) } label: {
                        Label(item.inCart ? "Back to list" : "In cart", systemImage: item.inCart ? "arrow.uturn.left" : "cart")
                    }
                    .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    if mode != .cart {
                        Button(role: .destructive) { model.delete(item.id) } label: { Label("Delete", systemImage: "trash") }
                        Button { model.snooze(item.id) } label: { Label("Snooze", systemImage: "clock") }.tint(.gray)
                    }
                }
        }
    }

    @ViewBuilder
    private func suggestRow(store: String, items: [Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Due soon at \(store), add while you're there").font(.footnote).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(items) { item in
                            Button("+ \(item.name)") { model.toggleList(item.id) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private func groups(_ items: [Item]) -> [StoreGroup] {
        var by: [String: [Item]] = [:]
        for item in items { by[AppData.usualStore(item) ?? "", default: []].append(item) }
        return by.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return by[a]!.count != by[b]!.count ? by[a]!.count > by[b]!.count : a < b
        }.map { StoreGroup(store: $0, items: by[$0]!) }
    }

    private func subtotal(_ items: [Item]) -> String {
        let total = items.compactMap(AppData.estimatedLine).reduce(0, +)
        return total > 0 ? "≈ " + money(total) : ""
    }

    private func summary(_ now: [Item]) -> String {
        let total = now.compactMap(AppData.estimatedLine).reduce(0, +)
        let unpriced = now.filter { AppData.estimatedLine($0) == nil }.count
        var text = "\(now.count) to buy"
        if total > 0 { text += ", about \(money(total))" + (unpriced > 0 ? " plus \(unpriced) unpriced" : "") }
        return text
    }

    /// Pantry items whose names start with the word being typed.
    private var suggestions: [Item] {
        let last = newItems.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let typed = Words.norm(last.replacingOccurrences(of: "^\\s*\\d+\\s*", with: "", options: .regularExpression))
        guard typed.count >= 2 else { return [] }
        return Array(model.data.items.filter { Words.norm($0.name).hasPrefix(typed) && Words.norm($0.name) != typed }.prefix(5))
    }

    private func complete(with name: String) {
        var parts = newItems.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let qty = parts.last?.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber } ?? ""
        parts[parts.count - 1] = (parts.count > 1 ? " " : "") + (qty.isEmpty ? "" : "\(qty) ") + name
        newItems = parts.joined(separator: ",")
    }

    private func add() {
        model.addFromText(newItems)
        newItems = ""
    }
}

struct FinishTripView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = ""
    @State private var date = Date()
    @State private var totals: [String: String] = [:]

    private var cart: [Item] { model.data.items.filter(\.inCart) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Store", text: $store)
                        let known = model.data.knownStores()
                        if !known.isEmpty {
                            Menu {
                                ForEach(known, id: \.self) { s in Button(s) { store = s } }
                            } label: { Image(systemName: "chevron.up.chevron.down") }
                        }
                    }
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                }
                Section {
                    ForEach(cart) { item in
                        HStack {
                            Text(item.name)
                            if item.quantityOnList > 1 { Text("×\(item.quantityOnList)").foregroundStyle(.secondary) }
                            Spacer()
                            TextField("—", text: Binding(get: { totals[item.id] ?? "" }, set: { totals[item.id] = $0 }))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                } header: {
                    HStack { Text("Line totals"); Spacer(); Text(sum > 0 ? money(sum) : "") }
                } footer: {
                    Text("Prefilled from what you last paid at this store. Correct anything that changed, or leave it blank.")
                }
            }
            .navigationTitle("Finish trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.finishTrip(store: store.trimmingCharacters(in: .whitespaces), date: Day(date: date), lineTotals: totals.compactMapValues(parseAmount))
                        dismiss()
                    }
                }
            }
            .onAppear {
                var counts: [String: Int] = [:]
                for item in cart { if let s = AppData.usualStore(item) { counts[s, default: 0] += 1 } }
                store = counts.max { $0.value < $1.value }?.key ?? ""
                prefill()
            }
            .onChange(of: store) { prefill() }
        }
    }

    private var sum: Double { totals.values.compactMap(parseAmount).reduce(0, +) }

    private func prefill() {
        for item in cart {
            if let price = AppData.lastPrice(item, store: store.isEmpty ? nil : store) {
                totals[item.id] = String(format: "%.2f", price * Double(item.quantityOnList))
            }
        }
    }
}
