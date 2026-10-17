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
- **Hide from the network** (optional). Uncheck *Visible to other devices* in
  Preferences (or in the menu bar) to stop advertising the Mac, so other devices
  no longer see it or can send to it. You can still send files and the clipboard
  from this Mac while hidden.

Everything lives in the menu bar. There is no dock icon and no main window.

## Requirements

- macOS 12 or later.
- Mac and Android device on the **same Wi‑Fi / LAN**.
- **Xcode 15 or later** is recommended, and is required for the Finder Share
  extension and the full asset catalog. The menu bar app itself can be built
  with only the Command Line Tools — see below.

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

### Building without Xcode

If you only have the Command Line Tools, you can still build a runnable app
bundle. The menu bar app, its UI, and the protocol core do not need Interface
Builder:

```sh
./scripts/build-app-without-xcode.sh
open build/QuickShare.app
```

This links against the SwiftPM build of `QuickShareKit` and assembles
`build/QuickShare.app` by hand. The one thing it leaves out is the Finder
**Share extension**, whose UI is a `.xib` and therefore needs Xcode's Interface
Builder. Use the Xcode project if you want the Share extension.

## Making your Android device visible

Android only starts advertising itself to Macs after it receives a Bluetooth LE
beacon that macOS applications are not allowed to send. In practice you make the
connection happen from the Android side:

- **Samsung devices:** scan the QR code shown by QuickShare (menu in the share
  sheet). This is the only option on many Samsung phones.
- **Other devices:** open the *Google Files* app and tap **Quick Share**, or use
  the *Quick Share* quick settings tile.

## Troubleshooting

**My Android device doesn't see my Mac.** The Mac makes itself discoverable by
advertising a Bonjour service on the LAN, so check, in order:

1. **Both devices on the same network** — the same SSID, not a guest network, and
   not one on Wi‑Fi while the other is on Ethernet behind a different subnet.
2. **The Mac is not hidden.** Menu bar → *Visible to everyone on this network*
   must be checked (and *Visible to other devices* in Preferences).
3. **Local Network permission (macOS 15+).** System Settings → Privacy &
   Security → Local Network → make sure QuickShare is allowed. Without it the
   system silently blocks all Bonjour traffic.
4. **Router isolation.** Many routers have "AP/client isolation" or an
   "isolate clients" option that stops devices from talking to each other; some
   public/hotel networks do this. mDNS dies with it.
5. **VPNs and firewalls.** An active VPN on either device can capture or block
   multicast. The macOS firewall should be off (or QuickShare allowed).
6. Give Android a few seconds with the Quick Share sheet open, and make sure
   Google Play services is up to date.

You can confirm the Mac side from Terminal — a healthy Mac prints one instance:

```sh
dns-sd -B _FC9F5ED42C8A._tcp
```

**A text/OTP share was rejected as "attachment type not supported".** Android
labels text shares as plain text, a URL, a phone number or an address, and
sometimes leaves it unclassified (OTPs are usually marked as sensitive text or a
phone number). QuickShare accepts all of these — non-links go to the clipboard —
and always sets a title when sending text back.

## Repository layout

```
QuickShare.xcodeproj    Xcode project (app + share extension + kit)
QuickShare/             Menu bar app (AppDelegate, Preferences, History, resources)
QuickShareKit/          Nearby Share protocol core (send + receive, clipboard)
ShareExtension/         macOS Share extension used for "share files to Android"
scripts/                Helper scripts (no-Xcode app build)
docs/PROTOCOL.md        Notes on how the protocol works
Package.swift           SwiftPM manifest for building QuickShareKit standalone
```

## Limitations

These are inherited from the protocol/OS, not from this app:

- **Wi‑Fi LAN only.** Wi‑Fi Direct, Bluetooth and Wi‑Fi Aware interchangeably
  used by Google are not available to macOS apps.
- While visible, your Mac is **visible to everyone on the LAN**. Turn off
  *Visible to other devices* to hide it.
- Receiving requires the sender to be discoverable (see above).

## License

The QuickShare app code is MIT licensed (see [LICENSE](LICENSE)). The protocol
core under `QuickShareKit/` is derived from the public‑domain NearDrop project,
and the protobuf definitions come from Google under Apache‑2.0 — see
[NOTICE.md](NOTICE.md).
