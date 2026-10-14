import SwiftUI
import PhotosUI
import RestockKit

struct ScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var pasting = false
    @State private var pasteText = ""
    @State private var reading = false
    @State private var error: String?
    @State private var draft: ReceiptDraft?
    @State private var savedTrip: IDBox?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.viewfinder").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                        Text("Log a shop in one photo").font(.title3.bold())
                        Text("Items, prices, store and date are read on your iPhone, matched to your pantry, and linked to real products with nutrition facts.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                Section {
                    Button { showCamera = true } label: { Label("Scan a receipt", systemImage: "camera") }
                        .disabled(!DocumentScanner.isSupported)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose a photo", systemImage: "photo.on.rectangle") }
                    Button { pasting = true } label: { Label("Paste receipt text", systemImage: "doc.on.clipboard") }
                    Button { draft = model.makeDraft(from: ReceiptSamples.traderJoes) } label: { Label("Try a sample receipt", systemImage: "sparkles") }
                } footer: {
                    Text("Photos never leave your iPhone. Only item names are sent to Open Food Facts to find products.")
                }
                if reading {
                    Section { HStack { ProgressView(); Text("Reading the receipt…") } }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Scan receipt")
            .fullScreenCover(isPresented: $showCamera) {
                DocumentScanner { images in
                    showCamera = false
                    Task { await read(images) }
                } onCancel: {
                    showCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: photo) {
                guard let photo else { return }
                Task {
                    defer { self.photo = nil }
                    if let data = try? await photo.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        await read([image])
                    } else {
                        error = "That photo couldn't be opened."
                    }
                }
            }
            .sheet(isPresented: $pasting) {
                NavigationStack {
                    TextEditor(text: $pasteText)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal)
                        .navigationTitle("Paste receipt text")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pasting = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Read") {
                                    pasting = false
                                    draft = model.makeDraft(from: pasteText)
                                    pasteText = ""
                                }
                                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                }
            }
            .navigationDestination(item: $draft) { d in
                ReceiptReviewView(initial: d) { tripID in
                    draft = nil
                    savedTrip = IDBox(id: tripID)
                }
            }
            .navigationDestination(item: $savedTrip) { TripDetailView(tripID: $0.id) }
        }
    }

    private func read(_ images: [UIImage]) async {
        reading = true; error = nil
        defer { reading = false }
        var pages: [String] = []
        for image in images {
            if let text = try? await TextRecognizer.text(in: image), !text.isEmpty { pages.append(text) }
        }
        let text = pages.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "No text found. Try again with the receipt flat, well lit and filling the frame."
        } else {
            draft = model.makeDraft(from: text)
        }
    }
}

struct ReceiptReviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: ReceiptDraft
    let onSaved: (String) -> Void

    init(initial: ReceiptDraft, onSaved: @escaping (String) -> Void) {
        _draft = State(initialValue: initial)
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("Receipt") {
                LabeledContent("Store") { TextField("Store", text: $draft.store).multilineTextAlignment(.trailing) }
                DatePicker("Date", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                LabeledContent("Total") { TextField("0.00", text: $draft.total).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section {
                ForEach($draft.lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Include", isOn: $line.include).labelsHidden()
                            TextField("Item name", text: $line.name).font(.headline)
                        }
                        HStack {
                            Stepper("Qty \(line.qty)", value: $line.qty, in: 1...99).fixedSize()
                            Spacer()
                            TextField("0.00", text: $line.price).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        }
                        Picker("Aisle", selection: $line.category) {
                            ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                        }
                        Picker("Pantry item", selection: $line.match) {
                            Text("New item").tag(String?.none)
                            ForEach(options(for: line.name)) { item in Text(item.name).tag(Optional(item.id)) }
                        }
                    }
                    .opacity(line.include ? 1 : 0.45)
                    .padding(.vertical, 4)
                }
                .onDelete { draft.lines.remove(atOffsets: $0) }
                Button { draft.lines.append(.init(name: "", qty: 1, price: "", category: "Other", match: nil)) } label: { Label("Add a line", systemImage: "plus") }
            } header: {
                HStack { Text("Items"); Spacer(); Text(summary) }
            } footer: {
                Text("Untick anything that isn't an item. Matches you choose are remembered next time.")
            }
            Section {
                DisclosureGroup("Text read from the receipt") {
                    Text(draft.rawText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Check the receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let lines = draft.lines.filter { $0.include && !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.map {
                        AppData.ReceiptLine(name: $0.name, qty: $0.qty, lineTotal: parseAmount($0.price), category: $0.category, itemId: $0.match)
                    }
                    let id = model.saveReceipt(store: draft.store.trimmingCharacters(in: .whitespaces), date: Day(date: draft.date), total: parseAmount(draft.total), lines: lines)
                    onSaved(id)
                }
                .disabled(!draft.lines.contains { $0.include && !$0.name.isEmpty })
            }
        }
    }

    private var summary: String {
        let included = draft.lines.filter(\.include)
        let sum = included.compactMap { parseAmount($0.price) }.reduce(0, +)
        let total = parseAmount(draft.total)
        return "\(included.count) · \(money(sum))" + (total.map { " of \(money($0))" } ?? "")
    }

    private func options(for name: String) -> [Item] {
        let likely = Matching.best(name, in: model.data.items).map(\.item)
        let rest = model.data.items.filter { item in !likely.contains { $0.id == item.id } }.sorted { $0.name < $1.name }
        return likely + rest
    }
}

struct TripDetailView: View {
    @EnvironmentObject private var model: AppModel
    let tripID: String
    @State private var open: IDBox?

    var body: some View {
        if let trip = model.data.trips.first(where: { $0.id == tripID }) {
            List {
                let grades = gradeCounts(trip)
                if !grades.isEmpty {
                    Section("Nutri-Score of this shop") {
                        HStack(spacing: 14) {
                            ForEach(grades, id: \.grade) { g in
                                HStack(spacing: 4) { NutriScoreBadge(grade: g.grade); Text("×\(g.count)").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section {
                    ForEach(Array(trip.items.enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                    if trip.items.isEmpty {
                        Text("\(trip.itemCount ?? 0) items. Item detail wasn't kept for this trip.").foregroundStyle(.secondary)
                    }
                } footer: {
                    if trip.items.contains(where: { $0.itemId.map { model.lookups[$0] == .pending } ?? false }) {
                        Text("Matching products from Open Food Facts. This takes a few seconds per item.")
                    } else {
                        Text("Tap an item to pick its product or scan the barcode. Product data from Open Food Facts.")
                    }
                }
            }
            .navigationTitle(trip.store.isEmpty ? "Trip" : trip.store)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack {
                        Text(trip.store.isEmpty ? "Trip" : trip.store).font(.headline)
                        Text(trip.date.long + (trip.displayTotal.map { " · " + money($0) } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $open) { ItemDetailView(itemID: $0.id) }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "cart")
        }
    }

    @ViewBuilder
    private func row(_ line: TripLine) -> some View {
        let item = line.itemId.flatMap { model.data.item($0) }
        Button {
            if let item { open = IDBox(id: item.id) }
        } label: {
            HStack(spacing: 12) {
                if let product = item?.product {
                    ProductThumb(product: product)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name).lineLimit(2)
                        Text(productDetail(product))
                            .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    NutriScoreBadge(grade: product.grade)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                        if item.map({ model.lookups[$0.id] == .pending }) ?? false { ProgressView() }
                        else { Text(String(line.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(.secondary) }
                    }
                    .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                        Text(status(item)).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                VStack(alignment: .trailing) {
                    Text(money(line.price)).fontWeight(.semibold)
                    if line.qty > 1 { Text("×\(line.qty)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item == nil)
    }

    private func productDetail(_ product: Product) -> String {
        var parts: [String] = []
        if !product.brand.isEmpty { parts.append(product.brand) }
        if let kcal = product.nutrition.kcal { parts.append("\(Int(kcal.rounded())) kcal/100 g") }
        if !product.confirmed { parts.append("suggested") }
        return parts.joined(separator: " · ")
    }

    private func status(_ item: Item?) -> String {
        guard let item else { return "" }
        switch model.lookups[item.id] {
        case .pending: return "Finding product…"
        case .noMatch: return "No match yet · tap to choose"
        case .offline, .busy: return "Lookup failed · tap to retry"
        case nil: return "Tap to find the product"
        }
    }

    private func gradeCounts(_ trip: Trip) -> [(grade: String, count: Int)] {
        var counts: [String: Int] = [:]
        for line in trip.items {
            if let g = line.itemId.flatMap({ model.data.item($0)?.product?.grade }), !g.isEmpty { counts[g, default: 0] += 1 }
        }
        return counts.keys.sorted().map { ($0, counts[$0]!) }
    }
}

enum ReceiptSamples {
    static let traderJoes = """
    TRADER JOE'S
    1234 MARKET ST
    SAN FRANCISCO CA
    ORGANIC BANANAS          1.49
    WHOLE MILK 1 GAL         3.99
    LARGE EGGS DOZEN         4.49
    SOURDOUGH BREAD          4.99
    2 @ 3.49
    BABY SPINACH             6.98
    GREEK YOGURT             5.49
    COFFEE BEANS 12OZ       12.99
    SUBTOTAL                40.42
    TAX                      0.00
    TOTAL                   40.42
    VISA                    40.42
    THANK YOU FOR SHOPPING
    """
}
