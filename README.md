# QuickShare for macOS

A menu bar app that speaks Google's **Quick Share** (formerly **Nearby Share**)
protocol, so your Mac can exchange things with Android phones on the same Wi‑Fi
network.

It is built on the public‑domain protocol core from
[NearDrop](https://github.com/grishka/NearDrop) and adds the things NearDrop
leaves out — most importantly a proper **clipboard** story and a **PIN‑free**
accept flow. See [NOTICE.md](NOTICE.md) for attribution.

## What makes it different

| Behaviour | NearDrop | QuickShare |
|---|---|---|
| Receiving **text** | saves a `.txt` file | **copies straight to the clipboard** |
| Receiving a **link** | opens in the browser | opens in the browser |
| **PIN** | shown in the notification | **never shown** — just Accept / Decline |
| Accepting | notification with PIN | notification with Accept / Decline (optional auto‑accept) |
| Sending files to Android | Finder → Share → app | Finder → Share, **or** menu bar → *Send Files to ▸ …* |
| Sending the clipboard to Android | ✗ | **menu bar → *Send Clipboard to ▸ …*** |
| Recent transfer **history** | ✗ | **last 10 items, persisted across restarts** |
| **Launch at login** | ✗ | optional toggle in Preferences (macOS 13+) |
| QR code | ✓ | ✓ |

## Features

- **Received text goes to the clipboard.** Plain text messages are never written
  to disk; they land on your clipboard, and you get a notification with a
  preview.
- **Received links open directly in your default browser.**
- **No PIN.** Quick Share still performs the UKEY2 encrypted key exchange under
  the hood, but the out‑of‑band PIN is not surfaced. You simply get a
  notification and tap **Accept**.
- **Optional auto‑accept** in Preferences for a fully hands‑free flow.
- **Send files to Android.** Right‑click a file in Finder → *Share* → *QuickShare*,
  or use the menu bar → *Send Files to ▸*.
- **Send your clipboard to Android.** Menu bar → *Send Clipboard to ▸* and pick a
  discovered device. URLs are advertised to Android as tappable links, other
  text as a text snippet.
- **QR code** to make Android discover your Mac (handy on Samsung devices, see
  below).
- **Transfer history.** The menu bar keeps the last **10** transfers (received
  and sent) under *History*. Click an entry to act on it again — copy text back
  to the clipboard, reopen a link, or reveal a received/sent file in Finder. The
  list is stored in `UserDefaults`, so it survives relaunches; clear it any time
  with *History ▸ Clear History*.
- **Launch at login** (optional). Turn on *Launch QuickShare at login* in
  Preferences and the app starts in the menu bar as soon as you log in. This uses
  the modern `SMAppService` API, so it requires **macOS 13 or later**; on older
  systems the option is shown as unavailable.

Everything lives in the menu bar. There is no dock icon and no main window.

## Requirements

- macOS 12 or later.
- Mac and Android device on the **same Wi‑Fi / LAN**.
- **Xcode 15 or later** to build the app bundle (the share extension and the app
  target need a full Xcode install — the Command Line Tools alone are not
  enough). The protocol core also builds on its own with SwiftPM.

## Building

```sh
open QuickShare.xcodeproj
```

Select the **QuickShare** scheme and run. Xcode will resolve the Swift package
dependencies (swift-protobuf, SwiftECC, QRCode) on first build.

Because the app is not notarized/signed with a developer certificate, the first
launch may be blocked by Gatekeeper — right‑click the app and choose **Open**.

To build just the protocol core (no Xcode required):

```sh
swift build
```

## Making your Android device visible

Android only starts advertising itself to Macs after it receives a Bluetooth LE
beacon that macOS applications are not allowed to send. In practice you make the
connection happen from the Android side:

- **Samsung devices:** scan the QR code shown by QuickShare (menu in the share
  sheet). This is the only option on many Samsung phones.
- **Other devices:** open the *Google Files* app and tap **Quick Share**, or use
  the *Quick Share* quick settings tile.

## Repository layout

```
QuickShare.xcodeproj    Xcode project (app + share extension + kit)
QuickShare/             Menu bar app (AppDelegate, Preferences, History, resources)
QuickShareKit/          Nearby Share protocol core (send + receive, clipboard)
ShareExtension/         macOS Share extension used for "share files to Android"
docs/PROTOCOL.md        Notes on how the protocol works
Package.swift           SwiftPM manifest for building QuickShareKit standalone
```

## Limitations

These are inherited from the protocol/OS, not from this app:

- **Wi‑Fi LAN only.** Wi‑Fi Direct, Bluetooth and Wi‑Fi Aware interchangeably
  used by Google are not available to macOS apps.
- While running, your Mac is **visible to everyone on the LAN**.
- Receiving requires the sender to be discoverable (see above).

## License

The QuickShare app code is MIT licensed (see [LICENSE](LICENSE)). The protocol
core under `QuickShareKit/` is derived from the public‑domain NearDrop project,
and the protobuf definitions come from Google under Apache‑2.0 — see
[NOTICE.md](NOTICE.md).
