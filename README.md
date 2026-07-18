<h1 align="center">BicSkin</h1>

<p align="center">
  <em>Screenshot-friendly BicCamera point card.<br/>
  Double-tap to flip to a bundled placeholder, DEBUG mode fakes the card number too — all client-side, zero server impact.</em>
</p>

<p align="center">
  <img alt="version" src="https://img.shields.io/badge/version-v0.1.0-2f80ed?style=flat-square" />
  <img alt="targets BicCamera" src="https://img.shields.io/badge/targets-BicCamera%205.4.3-ff66a3?style=flat-square" />
  <img alt="platform" src="https://img.shields.io/badge/platform-iOS%2014.0%2B-blue?style=flat-square" />
  <img alt="arch" src="https://img.shields.io/badge/arch-arm64%20rootless-555?style=flat-square" />
  <img alt="runs" src="https://img.shields.io/badge/runs-client--side%20only-1f9d55?style=flat-square" />
  <img alt="license" src="https://img.shields.io/badge/license-MIT-1f9d55?style=flat-square" />
</p>

---

**ビックカメラ (BicCamera)** is Bic Camera Inc.'s official iOS shopping app,
available on the [App Store](https://apps.apple.com/jp/app/id518593576).

BicSkin is a local screenshot-hygiene tweak for **BicCamera** that lets you
share the point-card screen without leaking your card number or barcode.
Double-tap the card image to flip between the real card art and a bundled
placeholder, and — in debug builds — the profile-fetch API response is
rewritten in place so the visible number, balance, and barcode are all
dummy values. Every change runs on-device and never touches the server or
the app's real account state.

<p align="center">
  <img src="docs/pointcard-bicame-musume.png" alt="Bicame Musume card art" width="240" />
  <img src="docs/pointcard-default.png" alt="Placeholder card" width="240" />
</p>

Both captures above are safe demo screens — the left card art is
BicCamera's own selectable *Bicame Musume* (ビッカメ娘) design, the right
is the bundled `pointcard_default` placeholder, and the barcode /
`0314 159 265 35` / `0 pt` / `2038-01-19` fields are all dummy values
injected by the DEBUG-only screenshot mode. Nothing here belongs to a
real account.

## Demo

Full 3D flip animation:

<div align="center">
  <video src="docs/demo.mov" controls muted playsinline width="320"></video>
</div>

If the inline player doesn't render for you, download
[docs/demo.mov](docs/demo.mov) and open it locally.

## Features

| Toggle | What it does |
|---|---|
| **Card Flip** | Double-tap the point-card image to flip between the real card and the bundled `pointcard_default` placeholder. Uses a manual `CATransform3D` Y-axis rotation so the card's rounded corners are preserved throughout the animation — `UIViewAnimationOptionTransitionFlip*` snapshots the layer and drops the mask mid-flip, so we walk the view hierarchy to find the rounded container and animate it directly instead. Scoped to the card + barcode block; the point-balance row below stays static. |
| **Dummy Data Injection** *(DEBUG only)* | Swizzles `NSJSONSerialization.JSONObjectWithData:` / `JSONObjectWithStream:` to rewrite the point-card record (`pointCardNumber`, `barcodeNumber`, `points`, `pointCardStatus`, expiry, promotions) with fixed dummy values before the app parses the response. Enabled in `DEBUG` builds, compiled out entirely by `FINALPACKAGE=1`. |

## Card Flip

The card image is a `UIImageView` nested inside a `PointCardViewCell`. The
first `setImage:` per instance (skipping views under 100k px so app icons
and thumbnails are ignored) attaches a double-tap `UITapGestureRecognizer`
and stashes the original image via associated objects. Each tap toggles a
process-global flag and re-invokes `setImage:` with either the stashed
original or the bundled `pointcard_default` asset.

The animation is intentionally *not* the built-in flip transition. UIKit's
`UIViewAnimationOptionTransitionFlipFromLeft/Right` takes a rectangular
snapshot of the layer and animates that — the layer's `cornerRadius +
masksToBounds` mask is dropped for the duration of the flip, so the
rectangular snapshot corners briefly show through around the rounded
card. BicSkin walks the superview chain from the image, picks the deepest
`cornerRadius > 0` ancestor that still contains the image, and runs a
two-stage `CATransform3D` Y-axis rotation on **its** layer directly. The
mask stays applied, and the halves are stitched by an `edgeOn` swap at
π/2 inside a `CATransaction { setDisableActions: YES }` so the implicit
`contents` fade doesn't leak.

## Dummy Data Injection *(DEBUG only)*

Debug builds swizzle `NSJSONSerialization`'s two class-method entry points
(`JSONObjectWithData:` and `JSONObjectWithStream:`). Any parsed dict is
inspected for point-card shape (presence of `pointCardNumber` /
`barcodeNumber`), and if matched, the entire user-card record is replaced
with a fixed dummy: card number `31415926535` (the first ten digits of
π), zero balance, no active promotions, expiry `2038-01-19`.

Card art (the image bytes) is **not** touched — the *Bicame Musume*
design in the screenshots above is BicCamera's own selectable point-card
artwork (choosable in ポイントカード設定), not something BicSkin injects.

In `FINALPACKAGE=1` builds the whole `#ifdef DEBUG` block is compiled out
— there is no runtime toggle and no code path that can fire it.

## Compatibility

BicCamera is an online shopping app — its point-card API schema is
unlikely to churn, but there is no guarantee. The recommended target is
always the **latest supported version**.

### Platform

| | |
|---|---|
| **Latest supported BicCamera** | `5.4.3` |
| **BicSkin minimum iOS** | 14.0 |
| **Tested on** | iOS 15.0 – 17, arm64 |
| **Distribution** | Jailbroken `.deb`, TrollStore jailed `.dylib`, Patched IPA (Sideloadly / AltStore) |

## Build

### Jailbroken device (rootless)

`make package install` transfers and installs the `.deb` over SSH.
Requires OpenSSH on both sides — `openssh-server` on the device (install
via Sileo / Zebra) and `ssh` on the host.

```sh
make package
make package install THEOS_DEVICE_IP=<device-ip>
```

### Jailed dylib (TrollStore)

TrollStore is only supported on specific iOS versions. Check the
[supported versions table](https://ios.cfw.guide/installing-trollstore/)
before proceeding.

```sh
make jailed
# -> packages/jailed/BicSkin.dylib
```

Stage inside the decrypted BicCamera `.app/Frameworks/`, add an
`LC_LOAD_DYLIB` entry pointing at it, then install via TrollStore.

### Patched IPA (Sideload)

For devices where TrollStore is unavailable. Install the patched IPA with
[Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/).

Requires a **decrypted** BicCamera IPA (e.g. obtained via
[palera1n](https://palera.in/) + Filza, or
[TrollDecrypt](https://github.com/donato-fiore/TrollDecrypt)). The App
Store download is FairPlay-encrypted and cannot be patched directly.

```sh
mkdir -p assets
cp ~/Downloads/BicCamera-5.4.3.ipa assets/
make deploy
```

## License

[MIT](LICENSE) © tkgstrator
