import SwiftUI
import RestockKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ShoppingListView()
                .tabItem { Label("Shopping", systemImage: "checklist") }
                .badge(model.nowCount)
            PantryView()
                .tabItem { Label("Pantry", systemImage: "cabinet") }
            ScanView()
                .tabItem { Label("Scan", systemImage: "doc.text.viewfinder") }
            SpendingView()
                .tabItem { Label("Spending", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                HStack(spacing: 16) {
                    Text(toast.message).font(.subheadline)
                    if toast.undo != nil {
                        Button("Undo") { model.undoLast() }.font(.subheadline.bold())
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .sensoryFeedback(.selection, trigger: model.hapticTick)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refresh() }
        }
    }
}

/// "2d overdue", "due tomorrow", "on list"…
struct StatusChip: View {
    let item: Item
    let prediction: Prediction
    let soonDays: Int

    var body: some View {
        Text(Predictor.statusLabel(item, prediction, soonDays: soonDays))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        if item.onList { return .green }
        switch prediction.status {
        case .overdue: return .red
        case .soon: return .orange
        case .ok: return .green
        case .unknown: return .secondary
        }
    }
}

/// The Restocked / Used / Buy soon control on every item.
struct StockPicker: View {
    @EnvironmentObject private var model: AppModel
    let item: Item
    let prediction: Prediction

    var body: some View {
        Picker("Stock level", selection: Binding(
            get: { Predictor.displayLevel(item, prediction) },
            set: { model.setLevel(item.id, $0) }
        )) {
            Text("Restocked").tag(StockLevel.stocked)
            Text("Used").tag(StockLevel.used)
            Text("Buy soon").tag(StockLevel.out)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct NutriScoreBadge: View {
    let grade: String
    var body: some View {
        if !grade.isEmpty {
            Text(grade.uppercased())
                .font(.subheadline.bold())
                .frame(width: 26, height: 26)
                .foregroundStyle(color)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Nutri-Score \(grade.uppercased())")
        }
    }
    private var color: Color {
        switch grade { case "a", "b": return .green; case "c": return .orange; default: return .red }
    }
}

struct ProductThumb: View {
    let product: Product?
    var fallback: String = "?"

    var body: some View {
        AsyncImage(url: product?.imageURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit().background(Color.white)
            } else {
                Text(String((product?.name ?? fallback).prefix(1)).uppercased())
                    .font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ProductRow: View {
    let product: Product
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ProductThumb(product: product)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name).lineLimit(2)
                let detail = [product.brand, product.qty].filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(.secondary) }
            NutriScoreBadge(grade: product.grade)
        }
    }
}
