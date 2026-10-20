# Third-party notices

## NearDrop (Quick Share receiving)
`mac/Sources/MandQuickShare` and `mac/Tests/MandQuickShareTests/TestSender.swift` are adapted from
[NearDrop](https://github.com/grishka/NearDrop) by Grishka, released into the public domain under the
[Unlicense](mac/Sources/MandQuickShare/NEARDROP_UNLICENSE.txt). M’AND's changes are marked “M’AND:”
(CryptoKit instead of SwiftECC/BigInt, no crashes on malformed input, safe file names and partial
files, size and count limits, links never opened automatically, receive-only).

The generated `Protobuf/*.pb.swift` files are derived from Google's Nearby protocol definitions,
Copyright Google LLC, licensed under the Apache License 2.0.

## Swift packages
- [swift-certificates](https://github.com/apple/swift-certificates), swift-asn1, swift-crypto: Apache-2.0
- [swift-protobuf](https://github.com/apple/swift-protobuf): Apache-2.0

## Android libraries
- AndroidX / Jetpack Compose: Apache-2.0
- [zxing-android-embedded](https://github.com/journeyapps/zxing-android-embedded): Apache-2.0
- kotlinx.serialization: Apache-2.0

## Tools used, not bundled
- [scrcpy](https://github.com/Genymobile/scrcpy) (Apache-2.0): installed by the user for screen mirroring.
