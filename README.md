# QuickShare for macOS

A menu bar app that speaks Google's **Quick Share** (formerly **Nearby Share**)
protocol, so your Mac can exchange things with Android phones on the same Wi‑Fi
network.

It is built on the public‑domain protocol core from
[NearDrop](https://github.com/grishka/NearDrop) and adds the things NearDrop
leaves out — most importantly a proper **clipboard** story and a **PIN‑free**
accept flow. See [NOTICE.md](NOTICE.md) for attribution.

## Download

Grab the latest **`QuickShare-<version>.dmg`** from the
[Releases](../../releases) page, open it, and drag **QuickShare** into
**Applications**.

The build is ad-hoc signed but **not notarized** (there is no paid Apple
Developer account behind it), so the first launch is blocked by Gatekeeper:

- **Right-click the app → Open**, then confirm — macOS remembers the choice for
  later launches.
- If that still doesn't stick:
  `xattr -dr com.apple.quarantine /Applications/QuickShare.app`

The prebuilt app is built for **Apple Silicon** and needs macOS 12 or later.
(On an Intel Mac, build it with Xcode instead — the Command Line Tools cannot
link Swift for x86_64.) It ships without the Finder **Share extension**, which
only the Xcode project builds; everything else, including *Send Files to ▸* and
*Send Clipboard to ▸* in the menu bar, works.

## What makes it different

| Behaviour | NearDrop | QuickShare |
|---|---|---|
| Receiving **text** | saves a `.txt` file | **copies straight to the clipboard** |
| Receiving a **link** | opens in the browser | opens in the browser |
| **PIN** | shown in the notification | **never shown** — just Accept / Decline |
| Accepting | notification with PIN | notification with Accept / Decline (optional auto‑accept) |
| Trusted devices | ✗ | **favourites auto‑accept silently, no notification** |
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
- **Favourite devices.** Add a device to your favourites and transfers from it
  are accepted automatically and **silently** — no notification at all. Trust a
  device straight from its transfer notification with **Always Accept**, or
  manage the list by name in Preferences.
- **Hide from the network** (optional). Uncheck *Visible to other devices* in
  Preferences (or in the menu bar) to stop advertising the Mac, so other devices
  no longer see it or can send to it. You can still send files and the clipboard
  from this Mac while hidden.

Everything lives in the menu bar. There is no dock icon and no main window.

## Requirements

- macOS 12 or later, on Apple Silicon or Intel.
- Mac and Android device on the **same Wi‑Fi / LAN**.
- Nothing else, to build the menu bar app — the Command Line Tools are enough.
  **Xcode** is only needed for the Finder Share extension (its UI is a `.xib`
  and needs Interface Builder).

## Building

```sh
make            # build build/QuickShare.app
make run        # build and launch it
make package    # build + QuickShare-<version>.dmg and .zip in build/
```

`make` runs `scripts/build-app-without-xcode.sh`: it builds the protocol core
with SwiftPM, compiles the app sources, renders `AppIcon.icns` from the asset
catalog, and assembles and ad-hoc-signs the bundle. No Interface Builder, no
asset-catalog compiler and no Xcode project required.

The result is **Apple Silicon only**: the Command Line Tools ship their Swift
compatibility libraries for arm64 alone, so with them not even a hello-world
Swift program links for x86_64.

With Xcode installed you can build the project instead. That also builds the
Finder Share extension, and can produce a universal binary:

```sh
make xcode      # or: open QuickShare.xcodeproj
```

Select the **QuickShare** scheme and run; Xcode resolves the Swift package
dependencies (swift-protobuf, SwiftECC, QRCode) on first build.

To build just the protocol core (no Xcode, no app):

```sh
swift build
```

### Icons

The app icon and the menu bar glyph are both generated from
`scripts/assets/Quickshare.svg` — the official Quick Share logo:

```sh
make icons
```

The app icon is the logo's blue circle; the menu bar gets a monochrome template
of the arrows, which macOS tints to match a light or dark menu bar.

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
Makefile                Build entry points: make app / run / package / icons
QuickShare.xcodeproj    Xcode project (app + share extension + kit)
QuickShare/             Menu bar app (AppDelegate, Preferences, History, resources)
QuickShareKit/          Nearby Share protocol core (send + receive, clipboard)
ShareExtension/         macOS Share extension used for "share files to Android"
scripts/                Build, icon and packaging scripts (see below)
docs/PROTOCOL.md        Notes on how the protocol works
Package.swift           SwiftPM manifest for building QuickShareKit standalone
```

The scripts, from the no-Xcode build path:

```
scripts/build-app-without-xcode.sh   Assemble and sign build/QuickShare.app
scripts/package-release.sh           Produce the .dmg and .zip in build/
scripts/make-icons.sh                Rasterise the logo and regenerate the icons
scripts/make-icons.swift             Crop, mask and size the icon set
scripts/assets/Quickshare.svg        The official logo the icons come from
```

## Limitations

These are inherited from the protocol/OS, not from this app:

- **Wi‑Fi LAN only.** Wi‑Fi Direct, Bluetooth and Wi‑Fi Aware interchangeably
  used by Google are not available to macOS apps.
- While visible, your Mac is **visible to everyone on the LAN**. Turn off
  *Visible to other devices* to hide it.
- **Favourites match on the device name.** The protocol does not expose a stable
  identifier on an incoming connection, so a trusted entry is a convenience, not
  a security boundary — anyone can claim a device name.
- Receiving requires the sender to be discoverable (see above).

## License

The QuickShare app code is MIT licensed (see [LICENSE](LICENSE)). The protocol
core under `QuickShareKit/` is derived from the public‑domain NearDrop project,
and the protobuf definitions come from Google under Apache‑2.0 — see
[NOTICE.md](NOTICE.md).
