# TV Remote for Apple Watch

A standalone Apple Watch app that controls **Google TV / Android TV, Roku,
Samsung and LG** televisions directly over Wi‑Fi. No iPhone app, no cloud, no
accounts: the watch speaks each TV's own local-network protocol, the same ones
the manufacturers' phone apps use.

- Works with several TVs; switch between them from the watch
- D‑pad, OK, Back, Home — tap for a press, hold for a long press where the TV supports it
- Digital Crown turns the volume up and down
- Play/pause, rewind, fast‑forward, previous/next, stop, mute
- Power, input, settings and one‑tap app launching (the TV's own app list on Roku and LG)
- Finds TVs on the network, pairs the way each brand expects, reconnects automatically

## Supported TVs

| Brand | Models | Pairing | Notes |
| ----- | ------ | ------- | ----- |
| Google TV / Android TV | Chromecast with Google TV, Android TV 11+ (Sony, TCL, Hisense, Nvidia Shield…) | Type the 6‑character code the TV shows | Long press, volume level, app deep links |
| Roku | Any Roku player or Roku TV | None | Power/volume/input only on Roku TVs; app list from the device |
| Samsung | Tizen TVs, 2016 and newer | Tap **Allow** on the TV | Token stored in the keychain; power‑on via Wake‑on‑LAN when the TV allows it |
| LG | webOS TVs, 2014 and newer | Tap **Allow** on the TV | Client key stored in the keychain; power‑on via Wake‑on‑LAN when enabled on the TV |

## How it works

| Brand | Transport | What the code does |
| ----- | --------- | ------------------ |
| Google TV | TLS on ports 6467 (pairing) and 6466 (remote), protobuf with varint framing | Generates an RSA client certificate, completes the Polo pairing handshake (secret = SHA‑256 over both public keys and the code nonce), then injects Android key events |
| Roku | HTTP on port 8060 (ECP) | `keypress`/`keydown`/`keyup`, `query/device-info`, `query/apps`, `launch` |
| Samsung | WebSocket `wss://…:8002/api/v2/channels/samsung.remote.control` (falls back to `ws` 8001) | `ms.remote.control` key clicks, token from `ms.channel.connect`, REST app launch |
| LG | WebSocket `ws://…:3000` or `wss://…:3001` (SSAP) | `register` with PROMPT pairing, pointer‑input socket for buttons, `ssap://` requests and subscriptions for volume, power and apps |

Everything protocol‑related lives in the `TVRemoteKit` Swift package; the
watch app is a SwiftUI layer over a single `TVController` protocol.

```
Packages/TVRemoteKit/
  Sources/
    TVRemoteCore/     TVController protocol, universal keys, saved TVs, keychain
                      secrets, SSDP + subnet-scan discovery, HTTP/WebSocket clients
    GoogleTVRemote/   Android TV Remote v2 + Polo pairing, certificate identity
    RokuRemote/       Roku ECP
    SamsungRemote/    Samsung Tizen remote WebSocket
    LGRemote/         LG webOS SSAP
  Tests/              58 unit tests; run on macOS or Linux with `swift test`
WatchRemote/          the watchOS app (SwiftUI)
project.yml           XcodeGen spec that produces the Xcode project
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
cd Packages/TVRemoteKit
swift test
```

## Adding a TV

1. Open the app. Google TVs appear under **Nearby** by themselves. Tap
   **Scan for Roku, Samsung, LG** to probe the local network for the others
   (takes up to a minute). Or pick the brand, type the TV's IP address and tap
   **Add**.
2. Follow the brand's pairing step:
   - **Google TV**: type the 6‑character code the TV shows. A wrong code clears
     the field so you can retype it.
   - **Samsung / LG**: a prompt appears on the TV; choose **Allow**.
   - **Roku**: nothing to do.
3. The remote screen appears. Add more TVs and switch between them from the
   last page.

## Troubleshooting

- **Scan finds nothing.** The watch must be on the same Wi‑Fi network as the TV.
  When the watch relays through a nearby iPhone over Bluetooth, local
  discovery can fail while direct connections still work, so enter the IP
  manually. Find it on the TV: Google TV Settings → System → About → Status;
  Roku Settings → Network → About; Samsung Settings → General → Network →
  Network Status → IP Settings; LG Settings → Network → Wi‑Fi Connection →
  Advanced.
- **"The TV didn't allow this remote."** Samsung or LG declined, or the TV's
  stored permission was removed (Samsung: Settings → General → External Device
  Manager → Device Connection Manager; LG: Settings → Connection → Mobile
  Connection Management). Forget the TV in the app and add it again.
- **"TV didn't answer. Is it paired?"** on Google TV usually means the TV no
  longer trusts the watch's certificate, for example after a factory reset.
  Forget the TV and pair again.
- **Power on doesn't work.** Roku players and Google TV wake over the network
  by themselves. Samsung needs *Power On with Mobile* and LG needs *Turn on via
  Wi‑Fi* enabled on the TV, and both are best‑effort from a watch.
- **Volume keys do nothing.** With HDMI‑CEC, volume may go to a sound bar;
  make sure CEC is enabled on both devices. Roku sticks and boxes have no volume
  control at all; only Roku TVs do.

## Limitations

- Voice search and text entry are not implemented on any platform.
- SSDP discovery needs Apple's multicast entitlement
  (`com.apple.developer.networking.multicast`). Without it the app relies on
  the subnet scan and manual entry, which work fine.
- Samsung TVs before 2016 (H/J series) and LG TVs before webOS 2 use different
  protocols and are not supported.
- The app trusts each TV's self‑signed certificate on every connection. The
  per‑brand pairing step is what proves both sides agreed; there is no extra
  pinning.

## License

MIT — see `LICENSE`.
