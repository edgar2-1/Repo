import SwiftUI
import Charts
import RestockKit

struct SpendingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var budgetText = ""

    private struct AisleSpend: Identifiable { let category: String; let amount: Double; var id: String { category } }

    var body: some View {
        let today = model.today
        let spent = model.data.spent(inMonthOf: today)
        let aisles = model.data.spendByCategory(lastDays: 90, today: today).prefix(8).map { AisleSpend(category: $0.category, amount: $0.amount) }
        let trips = model.data.trips.sorted { $0.date > $1.date }.prefix(20)
        let changes = model.data.priceChanges()
        NavigationStack {
            List {
                Section(today.asDate.formatted(.dateTime.month(.wide))) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(money(spent)).font(.largeTitle.bold())
                            if let budget = model.settings.budget { Text("of \(money(budget))").foregroundStyle(.secondary) }
                            else { Text("spent so far").foregroundStyle(.secondary) }
                        }
                        if let budget = model.settings.budget, budget > 0 {
                            let fraction = spent / budget
                            ProgressView(value: min(1, fraction)).tint(fraction > 1 ? .red : fraction > 0.85 ? .orange : .accentColor)
                            Text(budgetLine(spent: spent, budget: budget, today: today)).font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                TextField("Monthly budget, e.g. 500", text: $budgetText).keyboardType(.decimalPad)
                                Button("Set") {
                                    if let v = parseAmount(budgetText), v > 0 { model.updateSettings { $0.budget = v }; budgetText = "" }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if model.data.trips.isEmpty && aisles.isEmpty {
                    ContentUnavailableView("No spending yet", systemImage: "chart.bar", description: Text("Finish a trip or scan a receipt and your spending shows up here."))
                }

                if !aisles.isEmpty {
                    Section("By aisle, last 90 days") {
                        Chart(aisles) { row in
                            BarMark(x: .value("Spent", row.amount), y: .value("Aisle", row.category))
                                .foregroundStyle(Color.accentColor)
                                .cornerRadius(4)
                                .annotation(position: .trailing) {
                                    Text(money(row.amount)).font(.caption).foregroundStyle(.secondary)
                                }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(aisles.count) * 34 + 10)
                        .padding(.vertical, 6)
                    }
                }

                if !trips.isEmpty {
                    Section("Trips") {
                        ForEach(Array(trips)) { trip in
                            NavigationLink(value: IDBox(id: trip.id)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(trip.store.isEmpty ? "Unknown store" : trip.store)
                                        Text("\(trip.date.short) · \(trip.items.isEmpty ? (trip.itemCount ?? 0) : trip.items.count) items\(trip.source == .receipt ? " · scanned" : "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(money(trip.displayTotal)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !changes.isEmpty {
                    Section("Price changes") {
                        ForEach(changes, id: \.name) { c in
                            HStack {
                                Text(c.name)
                                Spacer()
                                Text("\(money(c.previous)) → \(money(c.latest))").font(.caption).foregroundStyle(.secondary)
                                Text("\(c.change > 0 ? "+" : "")\(Int((c.change * 100).rounded()))%")
                                    .font(.caption.bold())
                                    .foregroundStyle(c.change > 0 ? .red : .green)
                                    .frame(minWidth: 44, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Spending")
            .navigationDestination(for: IDBox.self) { TripDetailView(tripID: $0.id) }
        }
    }

    private func budgetLine(spent: Double, budget: Double, today: Day) -> String {
        let cal = Calendar.current
        let date = today.asDate
        let daysInMonth = cal.range(of: .day, in: .month, for: date)?.count ?? 30
        let left = daysInMonth - today.day
        let pace = spent / Double(max(1, today.day)) * Double(daysInMonth)
        let status = spent > budget ? "\(money(spent - budget)) over budget" : "\(money(budget - spent)) left"
        return "\(status) · \(left) days to go · on pace for \(money(pace))"
    }
}
