import SwiftUI
import RestockKit

struct ItemDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    @State private var addingPurchase = false
    @State private var purchaseDate = Date()
    @State private var purchaseQty = 1
    @State private var purchasePrice = ""
    @State private var purchaseStore = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let item = model.data.item(itemID) {
                    form(item)
                } else {
                    ContentUnavailableView("Item deleted", systemImage: "trash")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func form(_ item: Item) -> some View {
        let p = model.data.prediction(item, today: model.today)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.title2.bold())
                    Text(AppData.usualStore(item).map { "\(item.category) · usually \($0)" } ?? item.category)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                StockPicker(item: item, prediction: p)
                HStack {
                    fact(intervalText(p), intervalLabel(p))
                    Divider()
                    fact(dueText(p), "next due")
                    Divider()
                    fact(AppData.lastPrice(item, store: AppData.usualStore(item)).map(money) ?? "—", "last price")
                }
            }

            Section {
                Stepper(value: model.itemBinding(itemID, \.listQty, map: { max(1, $0 ?? 1) }, back: { $0 }), in: 1...99) {
                    HStack { Text("Quantity"); Spacer(); Text("\(item.quantityOnList)").foregroundStyle(.secondary) }
                }
                Button(item.inCart ? "In the cart" : item.onList ? "Remove from list" : "Add to list") { model.toggleList(itemID) }
                    .disabled(item.inCart)
                LabeledContent("Usual store") {
                    TextField(AppData.autoStore(item).map { "Auto: \($0)" } ?? "Auto", text: model.textBinding(itemID, \.store))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Note") {
                    TextField("Brand, size…", text: model.textBinding(itemID, \.notes)).multilineTextAlignment(.trailing)
                }
            } header: { Text("On the list") }

            ProductSection(item: item)

            let prices = AppData.pricesByStore(item)
            if !prices.isEmpty {
                Section("Price by store") {
                    ForEach(Array(prices.enumerated()), id: \.offset) { i, sp in
                        HStack {
                            Text(sp.store)
                            if i == 0 && prices.count > 1 {
                                Text("lowest").font(.caption.bold()).foregroundStyle(.green)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                            }
                            Spacer()
                            Text(sp.date.short).font(.caption).foregroundStyle(.secondary)
                            Text(money(sp.price)).frame(minWidth: 64, alignment: .trailing)
                        }
                    }
                }
            }

            Section {
                if addingPurchase {
                    DatePicker("Date", selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                    Stepper("Quantity: \(purchaseQty)", value: $purchaseQty, in: 1...99)
                    LabeledContent("Price each") { TextField("Optional", text: $purchasePrice).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    LabeledContent("Store") { TextField("Optional", text: $purchaseStore).multilineTextAlignment(.trailing) }
                    Button("Save purchase") {
                        model.addPurchase(itemID, Purchase(date: Day(date: purchaseDate), qty: purchaseQty, price: parseAmount(purchasePrice), store: purchaseStore.trimmingCharacters(in: .whitespaces)))
                        addingPurchase = false
                    }
                    .bold()
                }
                let history = item.purchases.enumerated().sorted { $0.element.date > $1.element.date }
                if history.isEmpty && !addingPurchase {
                    Text("No purchases recorded.").foregroundStyle(.secondary)
                }
                ForEach(history, id: \.offset) { index, purchase in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(purchase.date.short)
                            if !purchase.store.isEmpty { Text(purchase.store).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if purchase.qty > 1 { Text("×\(purchase.qty)").foregroundStyle(.secondary) }
                        Text(money(purchase.price))
                    }
                    .swipeActions { Button(role: .destructive) { model.removePurchase(itemID, at: index) } label: { Label("Remove", systemImage: "trash") } }
                }
            } header: {
                HStack {
                    Text("History")
                    Spacer()
                    Button(addingPurchase ? "Cancel" : "Add purchase") {
                        purchaseDate = Date(); purchaseQty = 1; purchasePrice = ""; purchaseStore = AppData.usualStore(item) ?? ""
                        addingPurchase.toggle()
                    }
                    .font(.caption).textCase(nil)
                }
            }

            Section {
                LabeledContent("Name") { TextField("Name", text: model.itemBinding(itemID, \.name, map: { $0 }, back: { $0.isEmpty ? item.name : $0 })).multilineTextAlignment(.trailing) }
                Picker("Aisle", selection: model.itemBinding(itemID, \.category, map: { $0 }, back: { $0 })) {
                    ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Runs out every") {
                    HStack {
                        TextField("Auto", text: model.itemBinding(itemID, \.intervalDays, map: { $0.map(String.init) ?? "" }, back: { Int($0) }))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                        Text("days").foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Item") } footer: {
                if let learned = p.learned {
                    Text("Learned from \(p.count) purchases: \(Predictor.everyText(learned)). Leave blank to keep learning.")
                } else {
                    Text(p.count == 1 ? "One purchase so far. After the next one Restock can predict when you'll run out." : "No purchases yet. Set how often it runs out, or log a purchase.")
                }
            }

            Section {
                Button("Delete item", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
            }
            .confirmationDialog("Delete \(item.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { dismiss(); model.delete(itemID) }
            }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func intervalText(_ p: Prediction) -> String {
        guard let interval = p.interval else { return "—" }
        return "\(Int(interval.rounded())) d"
    }

    private func intervalLabel(_ p: Prediction) -> String {
        if p.source == .set { return "set by you" }
        return p.learned != nil ? "between buys" : "needs 2 buys"
    }

    private func dueText(_ p: Prediction) -> String {
        guard let due = p.due, let left = p.daysLeft else { return "—" }
        if left < 0 { return "\(-left)d late" }
        if left == 0 { return "Today" }
        return due.short
    }
}

extension AppModel {
    /// A binding to one field of an item, converting to and from the control's type.
    func itemBinding<T, V>(_ id: String, _ keyPath: WritableKeyPath<Item, T>, map: @escaping (T) -> V, back: @escaping (V) -> T) -> Binding<V> {
        Binding(
            get: { [unowned self] in
                guard let item = self.data.item(id) else { return map(Item(name: "", category: "Other")[keyPath: keyPath]) }
                return map(item[keyPath: keyPath])
            },
            set: { [unowned self] value in self.updateItem(id) { $0[keyPath: keyPath] = back(value) } }
        )
    }

    /// Optional text field: empty text is stored as nil.
    func textBinding(_ id: String, _ keyPath: WritableKeyPath<Item, String?>) -> Binding<String> {
        itemBinding(id, keyPath, map: { $0 ?? "" }, back: { let t = $0.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : $0 })
    }
}
