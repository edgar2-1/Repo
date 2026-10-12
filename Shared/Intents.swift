import Foundation
import AppIntents
import TVRemoteCore
import GoogleTVRemote

/// Actions Siri, Shortcuts, Lock Screen widgets and the watch complication can run.
enum TVAction: String, AppEnum {
    case playPause, play, pause, power, powerOff, mute, volumeUp, volumeDown
    case home, back, select, up, down, left, right

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "TV Action" }

    static var caseDisplayRepresentations: [TVAction: DisplayRepresentation] = [
        .playPause: "Play / Pause", .play: "Play", .pause: "Pause",
        .power: "Power", .powerOff: "Turn Off", .mute: "Mute",
        .volumeUp: "Volume Up", .volumeDown: "Volume Down",
        .home: "Home", .back: "Back", .select: "Select",
        .up: "Up", .down: "Down", .left: "Left", .right: "Right",
    ]

    var key: TVKey {
        switch self {
        case .playPause: return .playPause
        case .play: return .play
        case .pause: return .pause
        case .power: return .power
        case .powerOff: return .powerOff
        case .mute: return .mute
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        case .home: return .home
        case .back: return .back
        case .select: return .select
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

/// "Hey Siri, pause the TV" and friends.
struct SendTVActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Control TV"
    static var description = IntentDescription("Sends a remote action to one of your TVs.")
    static var openAppWhenRun = false

    @Parameter(title: "Action")
    var action: TVAction

    @Parameter(title: "TV", description: "Leave empty for the TV you used last.")
    var tvName: String?

    init() {}

    init(action: TVAction, tvName: String? = nil) {
        self.action = action
        self.tvName = tvName
    }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) on \(\.$tvName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let runner = IntentRunner()
        do {
            let tv = try await runner.send(action.key, tvName: tvName)
            return .result(dialog: "Sent \(Self.name(for: action)) to \(tv.name).")
        } catch IntentRunner.Failure.noTVs {
            return .result(dialog: "Add a TV in TV Remote first.")
        } catch IntentRunner.Failure.unknownTV(let name) {
            return .result(dialog: "I couldn't find a TV called \(name).")
        } catch {
            return .result(dialog: "Couldn't reach the TV: \(ErrorText.describe(error))")
        }
    }

    private static func name(for action: TVAction) -> String {
        guard let title = TVAction.caseDisplayRepresentations[action]?.title else { return action.rawValue }
        return String(localized: title)
    }
}

/// Phrases Siri recognises without setup.
struct TVRemoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendTVActionIntent(action: .playPause),
            phrases: ["Pause the TV with \(.applicationName)", "Play the TV with \(.applicationName)", "Pause \(.applicationName)"]
        )
        AppShortcut(
            intent: SendTVActionIntent(action: .power),
            phrases: ["Turn off the TV with \(.applicationName)", "Turn on the TV with \(.applicationName)", "Toggle the TV with \(.applicationName)"]
        )
        AppShortcut(
            intent: SendTVActionIntent(action: .mute),
            phrases: ["Mute the TV with \(.applicationName)"]
        )
    }
}

/// Runs one action against a saved TV without the app UI. Used by intents,
/// which may execute in the widget extension process, so it reads TVs from the
/// shared container and credentials from the shared keychain group.
@MainActor
final class IntentRunner {
    enum Failure: Error {
        case noTVs
        case unknownTV(String)
    }

    func send(_ key: TVKey, tvName: String?) async throws -> SavedTV {
        KeychainConfig.accessGroup = ComplicationState.appGroupID.flatMap { $0.hasPrefix("$(") ? nil : $0 }
        let defaults = ComplicationState.sharedDefaults ?? .standard
        let saved = SavedTVStore(defaults: defaults)
        let tvs = saved.tvs
        guard !tvs.isEmpty else { throw Failure.noTVs }

        let tv: SavedTV
        if let tvName, !tvName.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let match = tvs.first(where: { $0.name.localizedCaseInsensitiveContains(tvName) }) else {
                throw Failure.unknownTV(tvName)
            }
            tv = match
        } else {
            tv = tvs.first { $0.id == saved.selectedID } ?? tvs[0]
        }

        let controller = try ControllerFactory.make(for: tv, credential: SecretStore.shared.credential(for: tv.id)) {
            try ClientIdentity.loadOrCreate()
        }
        defer { controller.disconnect() }
        try await withTimeout(seconds: 10) { try await controller.connect() }
        try await controller.send(key, phase: .tap)
        // Give the TV a moment to act before the socket closes.
        try? await Task.sleep(for: .milliseconds(150))
        return tv
    }
}
