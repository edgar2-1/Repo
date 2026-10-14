import SwiftUI
import RestockKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var restoring = false
    @State private var restoreText = ""
    @State private var restoreError: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Running-low alerts", isOn: Binding(
                        get: { model.settings.notifications },
                        set: { on in
                            if on {
                                Task {
                                    let granted = await Notifications.requestPermission()
                                    model.updateSettings { $0.notifications = granted }
                                    if !granted { model.show("Allow notifications for Restock in the Settings app.") }
                                }
                            } else {
                                model.updateSettings { $0.notifications = false }
                            }
                        }
                    ))
                    Stepper(value: setting(\.soonDays), in: 0...14) {
                        LabeledContent("Warn me ahead", value: model.settings.soonDays == 1 ? "1 day" : "\(model.settings.soonDays) days")
                    }
                    Picker("Alert time", selection: setting(\.reminderHour)) {
                        ForEach(6..<22, id: \.self) { h in Text(hourLabel(h)).tag(h) }
                    }
                    Toggle("Count on app icon", isOn: Binding(
                        get: { model.settings.badge },
                        set: { on in
                            Task {
                                let granted = on ? await Notifications.requestPermission() : true
                                model.updateSettings { $0.badge = on && granted }
                            }
                        }
                    ))
                } header: { Text("Reminders") } footer: {
                    Text("Restock alerts you when items are about to run out, and the app icon shows how many items to buy.")
                }

                Section {
                    Picker("Shopping day", selection: setting(\.shopDay)) {
                        Text("None").tag(Int?.none)
                        ForEach(0..<7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d]).tag(Optional(d)) }
                    }
                    if model.settings.shopDay != nil {
                        DatePicker("Time", selection: shopTime, displayedComponents: .hourAndMinute)
                    }
                } footer: { Text("A weekly reminder to check your list before you shop.") }

                Section("Budget & products") {
                    LabeledContent("Monthly budget") {
                        TextField("None", text: Binding(
                            get: { model.settings.budget.map { String(format: "%.0f", $0) } ?? "" },
                            set: { v in model.updateSettings { $0.budget = parseAmount(v).flatMap { $0 > 0 ? $0 : nil } } }
                        ))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Toggle("Find products after a scan", isOn: setting(\.autoProducts))
                }

                Section {
                    ShareLink(item: model.backupJSON(), preview: SharePreview("Restock backup")) {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                    Button { restoring = true } label: { Label("Restore from backup", systemImage: "square.and.arrow.down") }
                } header: { Text("Backup") } footer: {
                    Text("Everything is stored on this iPhone. A backup from the Restock web app can be restored here too.")
                }

                Section {
                    Button("Load example pantry") { model.loadSample() }
                    Button("Delete everything", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("\(model.data.items.count) items, \(model.data.items.reduce(0) { $0 + $1.purchases.count }) purchases, \(model.data.trips.count) trips.")
                }

                Section("About") {
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        LabeledContent("Product data", value: "Open Food Facts")
                    }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("Your lists, purchases and receipts stay on this iPhone. Receipt photos are read on the device and never uploaded. To find products, only the item name is sent to Open Food Facts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("Delete all items, purchases and trips?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.deleteEverything() }
            }
            .sheet(isPresented: $restoring) {
                NavigationStack {
                    VStack(alignment: .leading) {
                        TextEditor(text: $restoreText)
                            .font(.system(.caption, design: .monospaced))
                            .overlay(alignment: .topLeading) {
                                if restoreText.isEmpty { Text("Paste a backup here").foregroundStyle(.tertiary).padding(8).allowsHitTesting(false) }
                            }
                        if let restoreError { Text(restoreError).foregroundStyle(.red).font(.footnote) }
                    }
                    .padding()
                    .navigationTitle("Restore backup")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { restoring = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Restore") {
                                do { try model.restore(from: restoreText); restoreText = ""; restoreError = nil; restoring = false }
                                catch { restoreError = "That doesn't look like a Restock backup." }
                            }
                            .disabled(restoreText.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func setting<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { v in model.updateSettings { $0[keyPath: keyPath] = v } })
    }

    private var shopTime: Binding<Date> {
        Binding(
            get: {
                let parts = (model.settings.shopTime ?? "10:00").split(separator: ":").compactMap { Int($0) }
                return Calendar.current.date(bySettingHour: parts.first ?? 10, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.updateSettings { $0.shopTime = String(format: "%02d:%02d", c.hour ?? 10, c.minute ?? 0) }
            }
        )
    }

    private func hourLabel(_ h: Int) -> String {
        (Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()).formatted(date: .omitted, time: .shortened)
    }
}
