# Third-party notices

## AirCard-iOS / AirliftFFI

This POC's real-device integration is based on the public project
[`Mak5er/AirCard-iOS`](https://github.com/Mak5er/AirCard-iOS), inspected at commit
`097a058c984ffc33ccb697b9dfe8058be3e86244`.

The following components are the only intended upstream reuse boundary:

- `AirliftFFI.xcframework` and its C API;
- the on-device RPPairing flow represented by `PairingController.swift`;
- loopback/LocalDevVPN compatibility concepts;
- Wallet artwork dimensions, destination path, and cache invalidation strategy.

AirCard-iOS is distributed under the MIT License:

> MIT License
>
> Copyright (c) 2026 Johnny Franks
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

The deliverable includes the upstream framework and the minimal pairing/network
sources needed for an iPhone-only build. The original MIT license is preserved
at `SkinBridge-iOS/Vendor/AirCard-iOS-LICENSE`. The import script remains
available to refresh those files from a newer local AirCard-iOS checkout.

The vendored Rust source is modified to add `al_exploit_read_file`. This
extension reuses the upstream AirTraffic canary export sequence to copy one
protected artwork file into the app sandbox, then rewrites the exact bytes to
the source before returning. The modification remains covered by the same MIT
notice and is identified in this project rather than attributed to upstream.
