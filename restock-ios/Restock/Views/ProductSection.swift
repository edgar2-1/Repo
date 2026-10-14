import SwiftUI
import RestockKit

/// The matched Open Food Facts product: photo, Nutri-Score and nutrition facts.
struct ProductSection: View {
    @EnvironmentObject private var model: AppModel
    let item: Item

    @State private var candidates: [Product] = []
    @State private var searching = false
    @State private var message: String?
    @State private var barcode = ""
    @State private var scanning = false

    var body: some View {
        Section {
            if let product = item.product {
                ProductRow(product: product)
                if !product.confirmed {
                    HStack {
                        Text("Is this what you buy?").foregroundStyle(.secondary)
                        Spacer()
                        Button("Yes") { model.confirmProduct(item.id) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                NutritionTable(product: product)
                if let url = product.pageURL {
                    Link(destination: url) { Label("Ingredients and allergens", systemImage: "arrow.up.right.square") }
                }
                Button(product.confirmed ? "Change product" : "Choose another") { Task { await search() } }
                Button("Remove product", role: .destructive) { model.setProduct(item.id, nil); candidates = [] }
            } else {
                switch model.lookups[item.id] {
                case .pending: HStack { ProgressView(); Text("Finding the product…").foregroundStyle(.secondary) }
                case .noMatch: Text("No confident match. Search, or scan the barcode.").foregroundStyle(.secondary)
                case .offline: Text("Couldn't reach the product database.").foregroundStyle(.secondary)
                case .busy: Text("The product database is busy. Try again in a minute.").foregroundStyle(.secondary)
                case nil: Text("See the exact product, its photo and nutrition facts.").foregroundStyle(.secondary)
                }
                Button { Task { await search() } } label: { Label("Find product", systemImage: "magnifyingglass") }
                if BarcodeScanner.isAvailable {
                    Button { scanning = true } label: { Label("Scan barcode", systemImage: "barcode.viewfinder") }
                }
                HStack {
                    TextField("Or type the barcode number", text: $barcode).keyboardType(.numberPad)
                    Button("Look up") { Task { await lookUp(barcode) } }
                        .buttonStyle(.borderless)
                        .disabled(barcode.filter(\.isNumber).count < 6)
                }
            }
            if searching { HStack { ProgressView(); Text("Searching Open Food Facts…").foregroundStyle(.secondary) } }
            if let message { Text(message).foregroundStyle(.secondary) }
            if !candidates.isEmpty {
                Text("Tap the one you buy").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(candidates.enumerated()), id: \.offset) { _, product in
                    Button {
                        model.setProduct(item.id, product)
                        candidates = []
                    } label: {
                        ProductRow(product: product, trailing: product.nutrition.kcal.map { "\(Int($0.rounded())) kcal" })
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text("Product & nutrition")
        } footer: {
            Text("Product data from Open Food Facts, shared under the Open Database License.")
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                BarcodeScanner { code in
                    scanning = false
                    Task { await lookUp(code) }
                }
                .ignoresSafeArea()
                .navigationTitle("Scan barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
            }
        }
    }

    private func search() async {
        searching = true; message = nil; candidates = []
        defer { searching = false }
        do {
            let ranked = try await OpenFoodFacts.shared.candidates(for: item.name, store: AppData.usualStore(item))
            candidates = Array(ranked.prefix(6).map(\.product))
            if candidates.isEmpty { message = "Nothing found. Try renaming the item or scan the barcode." }
        } catch ProductLookupError.offline {
            message = "Couldn't reach the product database. Check your connection."
        } catch {
            message = "The product database is busy. Try again in a minute."
        }
    }

    private func lookUp(_ code: String) async {
        searching = true; message = nil
        defer { searching = false }
        do {
            if let product = try await OpenFoodFacts.shared.product(barcode: code) {
                model.setProduct(item.id, product)
                barcode = ""
                model.show("Product linked")
            } else {
                message = "That barcode isn't in Open Food Facts yet."
            }
        } catch {
            message = "Lookup failed. Check your connection and try again."
        }
    }
}

struct NutritionTable: View {
    let product: Product

    private struct Row: Identifiable { let label: String; let value: Double?; let unit: String; let indent: Bool; var id: String { label } }

    var body: some View {
        let n = product.nutrition
        if n.isEmpty {
            Text("No nutrition facts recorded for this product yet.").foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("NUTRITION FACTS")
                    Spacer()
                    Text("per 100 g" + (product.serving.isEmpty ? "" : " · serving \(product.serving)"))
                }
                .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 6)
                ForEach(rows(n)) { row in
                    Divider()
                    HStack {
                        Text(row.label).foregroundStyle(row.indent ? Color.secondary : Color.primary)
                        Spacer()
                        Text(format(row.value, row.unit)).fontWeight(row.indent ? .regular : .semibold)
                    }
                    .padding(.vertical, 6)
                    .padding(.leading, row.indent ? 14 : 0)
                }
            }
        }
    }

    private func rows(_ n: Nutrition) -> [Row] {
        [Row(label: "Calories", value: n.kcal, unit: "kcal", indent: false), Row(label: "Fat", value: n.fat, unit: "g", indent: false),
         Row(label: "Saturated fat", value: n.sat, unit: "g", indent: true), Row(label: "Carbohydrates", value: n.carbs, unit: "g", indent: false),
         Row(label: "Sugars", value: n.sugars, unit: "g", indent: true), Row(label: "Fiber", value: n.fiber, unit: "g", indent: true),
         Row(label: "Protein", value: n.protein, unit: "g", indent: false), Row(label: "Salt", value: n.salt, unit: "g", indent: false)]
    }

    private func format(_ v: Double?, _ unit: String) -> String {
        guard let v else { return "—" }
        if unit == "kcal" { return "\(Int(v.rounded())) kcal" }
        return (v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)).replacingOccurrences(of: ".0", with: "") + " " + unit
    }
}
