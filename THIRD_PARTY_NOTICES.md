# Third-party notices

## NearDrop (Quick Share receiving)
`mac/Sources/MandQuickShare` and `mac/Tests/MandQuickShareTests/TestSender.swift` are adapted from
[NearDrop](https://github.com/grishka/NearDrop) by Grishka, released into the public domain under the
[Unlicense](mac/Sources/MandQuickShare/NEARDROP_UNLICENSE.txt). M’AND's changes are marked “M’AND:”
(CryptoKit instead of SwiftECC/BigInt, no crashes on malformed input, safe file names and partial
files, size and count limits, links never opened automatically, receive-only).

The generated `Protobuf/*.pb.swift` files are derived from Google's Nearby protocol definitions,
Copyright Google LLC, licensed under the Apache License 2.0.

## TapDrop (Tap to Send)
The light-key idea, its thresholds and the notch sensor access in `mac/Sources/MandMacKit/Tap/` are adapted from
[TapDrop](https://github.com/0x1p0/TapDrop). Copyright (c) 2026 TapDrop contributors, MIT License:

> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
> persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright notice
> and this permission notice shall be included in all copies or substantial portions of the Software. THE SOFTWARE IS
> PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

## Swift packages
- [swift-certificates](https://github.com/apple/swift-certificates), swift-asn1, swift-crypto: Apache-2.0
- [swift-protobuf](https://github.com/apple/swift-protobuf): Apache-2.0

## Android libraries
- AndroidX / Jetpack Compose: Apache-2.0
- [zxing-android-embedded](https://github.com/journeyapps/zxing-android-embedded): Apache-2.0
- kotlinx.serialization: Apache-2.0

## Tools used, not bundled
- [scrcpy](https://github.com/Genymobile/scrcpy) (Apache-2.0): installed by the user for screen mirroring.
