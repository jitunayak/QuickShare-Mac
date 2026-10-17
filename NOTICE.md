# Attribution / Notices

QuickShare is an independent macOS implementation of Google's Quick Share
(formerly Nearby Share) protocol. It would not exist without the following:

## NearDrop (public domain)

The Nearby Share protocol implementation under `QuickShareKit/` — the UDP/key
exchange logic, the payload framing, the mDNS advertisement/discovery, and the
inbound/outbound connection state machines — is derived from
[NearDrop](https://github.com/grishka/NearDrop) by @grishka.

NearDrop is released into the public domain under the UNLICENSE:

> This is free and unencumbered software released into the public domain.
> Anyone is free to copy, modify, publish, use, compile, sell, or distribute
> this software, either in source code form or as a compiled binary, for any
> purpose, commercial or non-commercial, and by any means.

QuickShare extends that core with: clipboard-based text receiving, direct link
opening, a PIN-free accept flow, sending the clipboard to Android, and a
reworked menu bar / preferences UI.

The protocol description in `docs/PROTOCOL.md` is likewise from NearDrop and is
in the public domain.

## Google protobuf definitions (Apache License 2.0)

The `.proto` files under `QuickShareKit/ProtobufSource/` are from Google's
Nearby/Quick Share sources and Chromium, and are licensed under the Apache
License, Version 2.0. You may obtain a copy of the license at

    https://www.apache.org/licenses/LICENSE-2.0

The generated Swift files under `QuickShareKit/Protobuf/` are produced from
those `.proto` files with [SwiftProtobuf](https://github.com/apple/swift-protobuf).

## Third-party dependencies

- [swift-protobuf](https://github.com/apple/swift-protobuf) — Apache-2.0
- [SwiftECC](https://github.com/leif-ibsen/SwiftECC) — MIT
- [BigInt](https://github.com/leif-ibsen/BigInt) — MIT
- [ASN1](https://github.com/leif-ibsen/ASN1) — MIT
- [QRCode](https://github.com/dagronf/qrcode) — MIT
