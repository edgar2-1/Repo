# TV Remote for iPhone and Apple Watch

An iPhone app and an Apple Watch app that control **Google TV / Android TV,
Roku, Samsung and LG** televisions directly over Wi‑Fi. No cloud, no accounts:
both apps speak each TV's own local-network protocol, the same ones the
manufacturers' remote apps use. One install covers both devices, and the watch
also works on its own.

- Pair once on the phone; TVs, pairings and the Google TV identity sync to the watch
- Works with several TVs; switch between them on either device
- D‑pad, OK, Back, Home — tap for a press, hold for a long press where the TV supports it
- Digital Crown turns the volume up and down
- Play/pause, rewind, fast‑forward, previous/next, stop, mute
- Power, input, settings and one‑tap app launching (the TV's own app list on Roku and LG)
- Keyboard: type into search boxes and logins on the TV from the phone or by dictation on the watch
- Trackpad mode on the phone: swipe to move, tap to select; a volume slider where the TV reports its level
- Number pad for channel entry, pinned favorite apps, a color per TV
- Siri and Shortcuts: "Hey Siri, pause the TV with TV Remote"; actions also work from Lock Screen widgets
- Watch face complication that opens the remote, shows the selected TV, and on watchOS 10 has a play/pause button
- Double Tap on Apple Watch Series 9 and later plays or pauses
- Opens on the TV that is actually on when you have several
- Finds TVs on the network, pairs the way each brand expects, reconnects automatically

## Supported TVs

| Brand | Models | Pairing | Notes |
| ----- | ------ | ------- | ----- |
| Google TV / Android TV | Chromecast with Google TV, Android TV 11+ (Sony, TCL, Hisense, Nvidia Shield…) | Type the 6‑character code the TV shows | Long press, volume level, app deep links, text entry |
| Roku | Any Roku player or Roku TV | None | Power/volume/input only on Roku TVs; app list from the device; text entry |
| Samsung | Tizen TVs, 2016 and newer | Tap **Allow** on the TV | Token stored in the keychain; power‑on via Wake‑on‑LAN when the TV allows it; text entry (no remote backspace) |
| LG | webOS TVs, 2014 and newer | Tap **Allow** on the TV | Client key stored in the keychain; power‑on via Wake‑on‑LAN when enabled on the TV; text entry |

## How it works

| Brand | Transport | What the code does |
| ----- | --------- | ------------------ |
| Google TV | TLS on ports 6467 (pairing) and 6466 (remote), protobuf with varint framing | Generates an RSA client certificate, completes the Polo pairing handshake (secret = SHA‑256 over both public keys and the code nonce), then injects Android key events |
| Roku | HTTP on port 8060 (ECP) | `keypress`/`keydown`/`keyup`, `query/device-info`, `query/apps`, `launch` |
| Samsung | WebSocket `wss://…:8002/api/v2/channels/samsung.remote.control` (falls back to `ws` 8001) | `ms.remote.control` key clicks, token from `ms.channel.connect`, REST app launch |
| LG | WebSocket `ws://…:3000` or `wss://…:3001` (SSAP) | `register` with PROMPT pairing, pointer‑input socket for buttons, `ssap://` requests and subscriptions for volume, power and apps |

Everything protocol‑related lives in the `TVRemoteKit` Swift package. Both
apps are SwiftUI layers over a single `TVController` protocol and share their
model code (`Shared/`). WatchConnectivity mirrors the TV list, per‑TV
credentials and the Google TV client certificate between phone and watch, so
a TV added on one device is ready on the other.

```
Packages/TVRemoteKit/
  Sources/
    TVRemoteCore/     TVController protocol, universal keys, saved TVs, keychain
                      secrets, SSDP + subnet-scan discovery, HTTP/WebSocket clients
    GoogleTVRemote/   Android TV Remote v2 + Polo pairing, certificate identity
    RokuRemote/       Roku ECP
    SamsungRemote/    Samsung Tizen remote WebSocket
    LGRemote/         LG webOS SSAP
  Tests/              66 unit tests; run on macOS or Linux with `swift test`
Shared/               store, controller factory, discovery, pairing session,
                      WatchConnectivity sync, shared SwiftUI pieces
PhoneRemote/          the iPhone app (SwiftUI)
WatchRemote/          the Apple Watch app (SwiftUI)
WatchComplication/    watch face complication (WidgetKit)
project.yml           XcodeGen spec that produces the Xcode project
```

## Requirements

- iPhone running iOS 17 or later, and/or Apple Watch running watchOS 10 or later (Series 4 and newer)
- Xcode 15 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  (`brew install xcodegen`)
- A free or paid Apple Developer account for signing
- The watch and the TV on the same Wi‑Fi network

## Build and install

1. Generate and open the project:

   ```sh
   xcodegen generate
   open TVRemote.xcodeproj
   ```

2. Pick your team in **Signing & Capabilities** for all three targets, and
   change the identifiers: `PhoneRemote` from `com.example.TVRemote` to
   something unique, `WatchRemote` to that plus `.watchkitapp`, and
   `WatchComplication` to that plus `.watchkitapp.complication`. Also set
   the App Group on all three targets to `group.` plus your phone identifier;
   it shares saved TVs and credentials with Siri and the complication. The simplest way is to edit `project.yml` (bundle ids
   and `APP_GROUP_ID`) and run `xcodegen generate` again.

3. Choose the **PhoneRemote** scheme, select your iPhone and press Run. The
   watch app is embedded and installs alongside (Watch app → General → check
   *Automatic App Install*, or install it from the My Watch tab). The first
   install asks you to trust the developer certificate under Settings →
   General → VPN & Device Management.

To run only the watch app, choose the **WatchRemote** scheme and your watch.

To run the protocol tests without Xcode:

```sh
cd Packages/TVRemoteKit
swift test
```

## Adding a TV

Add TVs on whichever device is handy; they appear on the other within a few
seconds when both are nearby. The phone is the comfortable place to type a
Google TV code.

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

## Everyday extras

- **Trackpad.** On the phone, switch the segmented control above the pad to
  **Trackpad**. Swipe in any direction to move one step per 44 points; tap to
  select. The choice is remembered.
- **Volume.** Google TV and LG report the current level, so the phone shows a
  slider you can drag to a level. Roku and Samsung don't, so holding the
  volume buttons repeats instead.
- **Numbers.** The `#` button on the phone, or **Numbers** on the watch's last
  page, gives a channel keypad on TVs that have number keys.
- **Favorites.** Touch and hold an app on the phone to pin it to the front of
  the row; up to four per TV. Pinned apps show first on the watch too.
- **Colors.** Touch and hold a TV in the phone's settings to give it a color.
  The dot shows in the TV picker and the watch's TV list.
- **Siri.** "Pause the TV with TV Remote", "Turn off the TV with TV Remote",
  "Mute the TV with TV Remote". In the Shortcuts app the **Control TV** action
  takes any key and an optional TV name, so you can build "Movie night" or add
  a button to a Lock Screen widget. Siri uses the TV you used last unless you
  name one.
- **Double Tap.** On Apple Watch Series 9 / Ultra 2 and later, the Double Tap
  gesture presses play/pause on the media page. Needs the watchOS 11 SDK
  (Xcode 16) to build in.
- **Reconnecting.** The watch drops the connection when the screen sleeps.
  Taps made while **Reconnecting…** shows are kept and sent as soon as the link
  is back, usually under a second.

## Keyboard and complication

- **Keyboard.** Select a text field on the TV first (a search box, a login
  form), then tap the keyboard button on the phone or **Keyboard** on the
  watch's last page. Type, then **Send**; the return key submits. Samsung TVs
  accept text but have no remote backspace, so use the TV's own keyboard to
  correct mistakes there.
- **Complication.** Long‑press the watch face, tap a complication slot and
  choose **TV Remote**. It shows the selected TV and whether it is on, and
  tapping it opens the remote. It is available in circular, corner,
  rectangular and inline styles. On watchOS 10 and later the rectangular one
  carries a play/pause button that works without opening the app.

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
