import SwiftUI
import TVRemoteCore

/// Full-size remote for iPhone.
struct PhoneRemoteView: View {
    @EnvironmentObject private var store: RemoteStore
    @AppStorage("navigationMode") private var navigationMode = "dpad"
    @State private var showKeyboard = false
    @State private var showNumbers = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                StatusBanner()

                HStack(spacing: 16) {
                    RemoteButton(.power, systemImage: "power", size: 52, tint: .red.opacity(0.8), allowsHold: false)
                    RemoteButton(.input, systemImage: "rectangle.on.rectangle", size: 52, allowsHold: false)
                    RemoteButton(.assistant, systemImage: "mic.fill", size: 52, allowsHold: false)
                    RemoteButton(.settings, systemImage: "gearshape.fill", size: 52, allowsHold: false)
                    Button { showKeyboard = true } label: {
                        Image(systemName: "keyboard")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.textEntry.isEmpty)
                    .opacity(store.textEntry.isEmpty ? 0.3 : 1)
                }

                Picker("Navigation", selection: $navigationMode) {
                    Text("D-pad").tag("dpad")
                    Text("Trackpad").tag("trackpad")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                if navigationMode == "trackpad" {
                    TrackpadView()
                } else {
                    DPadCluster()
                }

                HStack(spacing: 28) {
                    RemoteButton(.back, systemImage: "arrow.uturn.backward", size: 60)
                    RemoteButton(.home, systemImage: "house.fill", size: 60)
                    RemoteButton(.menu, systemImage: "line.3.horizontal", size: 60)
                    Button { showNumbers = true } label: {
                        Image(systemName: "number")
                            .font(.system(size: 25, weight: .semibold))
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(Color.gray.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.supportedKeys.contains(.num1))
                    .opacity(store.supportedKeys.contains(.num1) ? 1 : 0.3)
                }

                MediaBar()

                VolumeRow()

                AppsRow()
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showKeyboard) {
            NavigationStack { TextEntryView() }
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showNumbers) {
            NavigationStack {
                NumberPadView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showNumbers = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }
}

/// Connection state above the controls. Hidden when connected.
private struct StatusBanner: View {
    @EnvironmentObject private var store: RemoteStore

    var body: some View {
        switch store.phase {
        case .connected, .noTVs:
            EmptyView()
        case .connecting:
            banner("Connecting…", color: .yellow, spinner: true)
        case .pairingPrompt:
            banner("Choose Allow on your TV", color: .orange, spinner: true)
        case .disconnected(let reason):
            Button { store.connect() } label: {
                banner(reason ?? "Disconnected. Tap to retry.", color: .red, spinner: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(_ text: String, color: Color, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().tint(.black) }
            Text(text).font(.footnote.weight(.medium))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(color.opacity(0.85)))
    }
}

/// Large D-pad: a ring of arrows around OK.
private struct DPadCluster: View {
    private let ring: CGFloat = 250
    private let arrow: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(width: ring, height: ring)
            RemoteButton(.up, systemImage: "chevron.up", size: arrow, tint: .clear)
                .offset(y: -ring / 2 + arrow / 2 + 8)
            RemoteButton(.down, systemImage: "chevron.down", size: arrow, tint: .clear)
                .offset(y: ring / 2 - arrow / 2 - 8)
            RemoteButton(.left, systemImage: "chevron.left", size: arrow, tint: .clear)
                .offset(x: -ring / 2 + arrow / 2 + 8)
            RemoteButton(.right, systemImage: "chevron.right", size: arrow, tint: .clear)
                .offset(x: ring / 2 - arrow / 2 - 8)
            RemoteButton(key: .select, size: 96, tint: .accentColor) {
                Text("OK").foregroundStyle(.white)
            }
        }
    }
}

private struct MediaBar: View {
    var body: some View {
        HStack(spacing: 18) {
            RemoteButton(.previous, systemImage: "backward.end.fill", size: 48)
            RemoteButton(.rewind, systemImage: "gobackward.10", size: 48)
            RemoteButton(.playPause, systemImage: "playpause.fill", size: 64, tint: .accentColor.opacity(0.85), allowsHold: false)
            RemoteButton(.fastForward, systemImage: "goforward.10", size: 48)
            RemoteButton(.next, systemImage: "forward.end.fill", size: 48)
        }
    }
}

private struct VolumeRow: View {
    @EnvironmentObject private var store: RemoteStore
    @State private var sliderValue: Double = 0
    @State private var editing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                RemoteButton(.volumeDown, systemImage: "speaker.minus.fill", size: 52, repeatsOnHold: true)
                RemoteButton(.mute, systemImage: "speaker.slash.fill", size: 52, allowsHold: false)
                RemoteButton(.volumeUp, systemImage: "speaker.plus.fill", size: 52, repeatsOnHold: true)
                RemoteButton(.channelDown, systemImage: "minus.rectangle", size: 52, repeatsOnHold: true)
                RemoteButton(.channelUp, systemImage: "plus.rectangle", size: 52, repeatsOnHold: true)
            }
            if let volume = store.volume, volume.max > 0 {
                // Google TV and LG report the level, so the slider is exact.
                HStack(spacing: 10) {
                    Image(systemName: volume.muted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $sliderValue, in: 0 ... Double(volume.max), step: 1) { isEditing in
                        editing = isEditing
                        if !isEditing { store.setVolume(Int(sliderValue)) }
                    }
                    .tint(volume.muted ? .gray : .accentColor)
                    Text("\(Int(sliderValue))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .onAppear { sliderValue = Double(volume.level) }
                .onChange(of: store.volume) { newValue in
                    if !editing, let level = newValue?.level { sliderValue = Double(level) }
                }
            } else {
                Text("Hold volume to repeat")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Horizontal strip of app shortcuts the TV can launch; pinned ones first.
private struct AppsRow: View {
    @EnvironmentObject private var store: RemoteStore

    private var orderedApps: [TVApp] {
        let favorites = store.favoriteApps
        return favorites + store.apps.filter { app in !favorites.contains(app) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps").font(.headline)
                Spacer()
                if let app = store.currentApp {
                    Text("Now: \(app)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if store.apps.isEmpty {
                Text(store.phase == .connected ? "This TV didn't report any apps." : "Connect to see apps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(orderedApps.prefix(40)) { app in
                            AppChip(app: app, pinned: store.isFavorite(app))
                        }
                    }
                }
                Text("Touch and hold an app to pin it first.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct AppChip: View {
    @EnvironmentObject private var store: RemoteStore
    let app: TVApp
    let pinned: Bool

    var body: some View {
        Button { store.launch(app) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: app.symbol)
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
                    if pinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .padding(4)
                    }
                }
                Text(app.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { store.toggleFavorite(app) } label: {
                Label(pinned ? "Unpin" : "Pin to front", systemImage: pinned ? "star.slash" : "star")
            }
        }
    }
}
