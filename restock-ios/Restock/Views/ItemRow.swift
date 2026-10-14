import SwiftUI
import RestockKit

struct ItemRow: View {
    enum Mode { case list, pantry, cart }

    @EnvironmentObject private var model: AppModel
    let item: Item
    let mode: Mode
    let onOpen: () -> Void

    var body: some View {
        let p = model.data.prediction(item, today: model.today)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if mode != .pantry {
                    Button {
                        withAnimation(.snappy) { model.toggleCart(item.id) }
                    } label: {
                        Image(systemName: item.inCart ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(item.inCart ? Color.accentColor : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.inCart ? "Take \(item.name) out of the cart" : "Put \(item.name) in the cart")
                }
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.name)
                                    .strikethrough(mode == .cart, color: .secondary)
                                    .foregroundStyle(mode == .cart ? Color.secondary : Color.primary)
                                if mode != .pantry && item.quantityOnList > 1 {
                                    Text("×\(item.quantityOnList)").foregroundStyle(.secondary)
                                }
                            }
                            let sub = subtitle(p)
                            if !sub.isEmpty && mode != .cart {
                                Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if mode == .cart {
                            Text(money(AppData.estimatedLine(item))).foregroundStyle(.secondary)
                        } else {
                            StatusChip(item: item, prediction: p, soonDays: model.settings.soonDays)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if mode != .cart {
                StockPicker(item: item, prediction: p)
                    .padding(.leading, mode == .list ? 40 : 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(_ p: Prediction) -> String {
        switch mode {
        case .list:
            let est = AppData.estimatedLine(item).map { "≈ " + money($0) }
            let parts = [item.notes, AppData.usualStore(item), est].compactMap { $0 }.filter { !$0.isEmpty }
            return parts.isEmpty ? item.category : parts.joined(separator: " · ")
        case .pantry:
            let grade = item.product.flatMap { $0.grade.isEmpty ? nil : "Nutri-Score " + $0.grade.uppercased() }
            return [Predictor.everyText(p.interval), p.last.map { "last " + $0.short } ?? "never bought", grade, item.notes]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .cart:
            return ""
        }
    }
}
