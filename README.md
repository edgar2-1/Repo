# Google TV Remote for Apple Watch

A standalone Apple Watch app that controls a Google TV (Chromecast with
Google TV, or any Android TV 11+ device) directly over Wi‑Fi. No iPhone app,
no cloud, no Google account: the watch speaks the same local protocol the
official Google TV remote app uses.

- D‑pad, OK, Back, Home — tap for a press, hold for a long press
- Digital Crown turns the volume up and down; the TV's volume level is shown
- Play/pause, rewind, fast‑forward, previous/next, stop, mute
- Power, input, Assistant, settings, and one‑tap app launching
  (YouTube, Netflix, Prime Video, Disney+, YouTube TV, Spotify, Plex)
- Finds the TV with Bonjour, pairs with the 6‑character on‑screen code,
  reconnects automatically

## How it works

Google TV exposes two TLS services on the LAN:

| Port | Protocol | Purpose |
| ---- | -------- | ------- |
| 6467 | Pairing ("Polo") v2 | One‑time pairing: the TV shows a code, the remote proves it saw it |
| 6466 | Android TV Remote v2 | Key injection, volume reports, app links, keep‑alive pings |

Both use protobuf messages with a varint length prefix. The remote is
identified by its TLS client certificate: on first launch the watch generates
a 2048‑bit RSA key and a self‑signed certificate and stores them in the
keychain. Pairing binds that certificate to the TV; the secret sent to the TV
is `SHA‑256(client modulus ‖ client exponent ‖ TV modulus ‖ TV exponent ‖ nonce)`
where the nonce is the last four hex digits of the on‑screen code and the first
two digits are a check byte. After that the TV accepts the certificate on port
6466 without further prompts.

Everything protocol‑related lives in the `GoogleTVRemoteKit` Swift package;
the watch app is a thin SwiftUI layer on top.

```
Packages/GoogleTVRemoteKit/
  Sources/GoogleTVRemoteKit/
    Protobuf/     hand‑rolled protobuf writer/reader (no runtime dependency)
    Protocol/     RemoteMessage, PairingMessage, KeyCode, varint framing
    Pairing/      PairingSecret (pure), PairingClient (network)
    Remote/       RemoteClient — handshake, pings, key injection, events
    Transport/    TLSConnection — Network.framework with client identity
    Identity/     certificate generation, keychain‑backed SecIdentity, RSA DER parsing
    Discovery/    TVBrowser — Bonjour `_androidtvremote2._tcp` + host resolution
  Tests/          33 unit tests; run on macOS or Linux with `swift test`
WatchRemote/      the watchOS app (SwiftUI)
project.yml       XcodeGen spec that produces the Xcode project
```

## Requirements

- Apple Watch running watchOS 9 or later (Series 4 or newer)
- Xcode 15 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`)
- A free or paid Apple Developer account for signing
- The watch and the TV on the same Wi‑Fi network

## Build and install

1. Generate and open the project:

   ```sh
   xcodegen generate
   open GoogleTVWatchRemote.xcodeproj
   ```

2. In the `WatchRemote` target's **Signing & Capabilities** tab pick your
   team, and change the bundle identifier from `com.example.GoogleTVWatchRemote`
   to something unique. (Or set `DEVELOPMENT_TEAM` and
   `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` and regenerate.)

3. Select your Apple Watch as the run destination and press Run. The first
   install asks you to trust the developer certificate on the watch
   (Settings → General → Device Management on the paired iPhone).

To run the protocol tests without Xcode:

```sh
cd Packages/GoogleTVRemoteKit
swift test
```

## Pairing

1. Open the app. TVs on the network appear under **Nearby**; tap yours. If
   nothing shows up, type the TV's IP address (Google TV: Settings → System →
   About → Status) and tap **Pair**.
2. The TV shows a 6‑character code. Type it on the watch's keypad. A wrong code
   simply clears the field so you can retype it.
3. Done. The remote screen appears and connects automatically from now on.

**Forget TV** in the last page removes the saved TV. **Forget & reset remote
identity** additionally generates a new certificate, so the TV sees the watch
as a brand‑new remote on the next pairing.

## Troubleshooting

- **No TVs found.** Bonjour discovery needs the watch to be on Wi‑Fi itself.
  When the watch relays traffic through a nearby iPhone over Bluetooth,
  multicast discovery may not work, but a direct connection does, so enter the
  IP manually.
- **"TV didn't answer. Is it paired?"** The TV dropped the connection during
  the handshake. This usually means the TV no longer trusts the certificate
  (for example after a TV factory reset). Forget the TV and pair again.
- **"No route to TV."** The watch has no path to that address. Check Wi‑Fi on
  the watch and that the TV's IP hasn't changed; re‑pairing with the newly
  discovered address fixes a changed IP.
- **Volume keys do nothing.** On TVs with HDMI‑CEC, volume keys go to the
  connected sound system; make sure CEC is enabled on both devices.

## Limitations

- Voice search streams audio over a separate channel that is not implemented;
  the mic button opens Assistant on the TV so you can use the TV's own mic if
  it has one.
- Text entry (the TV's on‑screen keyboard) is not implemented.
- The app trusts the TV's self‑signed certificate on every connection. Pairing
  is what proves both sides saw the same code; there is no additional pinning.

## License

MIT — see `LICENSE`.
