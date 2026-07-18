<h1 align="center">BicSkin</h1>

<p align="center">
  <em>Reveal the Bicame Musume (ビッカメ娘) point-card face on any account —<br/>
  normally you'd need to own that specific card to see it. All client-side, zero server impact.</em>
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

BicSkin is a local tweak for **BicCamera** that cycles the on-screen
point-card face with a double-tap. Two faces ship in v0.1.0 and the
list is designed to grow — the toggle state is stored as an index into
an ordered pool, not a boolean, so additional designs can be appended
without breaking anyone's persisted preference.

Current pool:

| Index | Face | Source |
|---|---|---|
| `0` | Plain default — BicCamera's `pointcard_default` watermark | app bundle via `imageNamed:` |
| `1` | *Bicame Musume* (ビッカメ娘) collaboration design | CDN prefetch |

The last index you flipped to is persisted to `NSUserDefaults`, so the
next launch starts on the same face — the tweak intercepts the first
`setImage:` on any view sitting inside a `PointCard`-named ancestor
(with a card-shaped aspect ratio so the barcode strip alongside isn't
swapped by accident) and substitutes the persisted choice before it
ever renders. Every change runs on-device and never touches the server
or your account state.

<p align="center">
  <img src="docs/pointcard-original.png" alt="Point card as this account normally shows it" width="240" />
  <img src="docs/pointcard-bicame-musume.png" alt="After flip: Bicame Musume face" width="240" />
</p>

Left: the point card as this account normally shows it (the plain
BicCamera default — this demo account doesn't own Bicame Musume).
Right: after a double-tap flip, the same card view is swapped for the
Bicame Musume design, pulled straight from BicCamera's CDN. The numeric
fields (`0314 159 265 35`, `0 pt`, expiry `2038-01-19`) aren't real —
see [Screenshot helper](#screenshot-helper-debug-only) below.

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
| **Card face flip** | Double-tap the point-card image to flip between the account's normally-fetched card art and the Bicame Musume design pulled from BicCamera's CDN. Uses a manual `CATransform3D` Y-axis rotation so the card's rounded corners are preserved throughout the animation. Scoped to the card + barcode block — the point-balance row below stays static. |

## Card face flip

The swap image is fetched once when the tweak loads
(`https://d1v4cay8lxkuwy.cloudfront.net/?storagekey=/images/pointCard/bicamemusume.png`)
on a background queue and cached in a process-global `UIImage`.
Hardcoding the URL keeps the tweak resilient to renames of BicCamera's
in-app asset catalog and avoids the `imageNamed:` fallback path
entirely. If the fetch fails, the double-tap is a no-op — the app's own
card art stays on screen.

The point-card image itself is a `UIImageView` inside a
`PointCardViewCell`. The first `setImage:` per instance (skipping views
under 100k px so app icons and thumbnails are ignored) attaches a
double-tap `UITapGestureRecognizer` and stashes the fetched image via an
associated object. Each tap toggles a process-global flag and re-invokes
`setImage:` with either the stashed original or the cached swap image.

The animation is intentionally *not* the built-in flip transition.
UIKit's `UIViewAnimationOptionTransitionFlipFromLeft/Right` takes a
rectangular snapshot of the layer and animates that — the
`cornerRadius + masksToBounds` mask is dropped for the duration of the
flip, so the rectangular snapshot corners briefly show through around
the rounded card. BicSkin walks the superview chain from the image,
picks the deepest `cornerRadius > 0` ancestor that still contains the
image, and runs a two-stage `CATransform3D` Y-axis rotation on **its**
layer directly. The mask stays applied, and the halves are stitched by
an `edgeOn` swap at π/2 inside a
`CATransaction { setDisableActions: YES }` so the implicit `contents`
fade doesn't leak.

## Screenshot helper *(DEBUG only)*

Not a feature — a build-time helper used to produce the screenshots and
demo video in this README without exposing the maintainer's real card.
`DEBUG` builds swizzle `NSJSONSerialization.JSONObjectWithData:` /
`JSONObjectWithStream:` and rewrite the parsed profile-fetch response
with fixed dummy values before the app sees it:

| Field | Dummy value |
|---|---|
| `pointCardNumber` | `31415926535` |
| `barcodeNumber` | `3141592653589` |
| `points` | `0` |
| `bicpayPoints` | `0` |
| `pointExpiration` | `2038-01-19` (Y2K38) |
| `bicpayPointExpiration` | `2077-01-01` |

`pointCardImage` and the other fields are passed through untouched.
In `FINALPACKAGE=1` builds the whole `#ifdef DEBUG` block is compiled
out — there is no runtime toggle and nothing that can fire it.

## Compatibility

BicCamera is an online shopping app — the recommended target is always
the **latest supported version**.

### Platform

| | |
|---|---|
| **Latest supported BicCamera** | `5.4.3` |
| **BicSkin minimum iOS** | 14.0 |
| **Tested on** | iOS 15.0 – 17, arm64 |
| **Distribution** | Jailbroken `.deb`, TrollStore-installable Patched IPA, Sideload-installable Patched IPA |

## Build

### Jailbroken device (rootless)

`make package install` transfers and installs the `.deb` over SSH.
Requires OpenSSH on both sides — `openssh-server` on the device (install
via Sileo / Zebra) and `ssh` on the host.

```sh
make package
make package install THEOS_DEVICE_IP=<device-ip>
```

### TrollStore

Requires a TrollStore-supported iOS version — check the
[supported versions table](https://ios.cfw.guide/installing-trollstore/)
before proceeding. `make deploy` builds the patched IPA, transfers it to
the device over SSH, and installs it via `trollstorehelper` in one shot.

```sh
mkdir -p assets
cp ~/Downloads/BicCamera-5.4.3.ipa assets/
make deploy
```

### Sideload (Sideloadly / AltStore)

For devices where TrollStore isn't available. Same flow as KiouForge's
Patched IPA path — build the IPA locally, then hand it off to your
sideload tool.

Requires a **decrypted** BicCamera IPA (e.g. via
[palera1n](https://palera.in/) + Filza or
[TrollDecrypt](https://github.com/donato-fiore/TrollDecrypt)) — App
Store downloads are FairPlay-encrypted and cannot be patched directly.

```sh
mkdir -p assets
cp ~/Downloads/BicCamera-5.4.3.ipa assets/
make ipa
# -> packages/ipa/BicSkin.ipa
```

Then load `packages/ipa/BicSkin.ipa` into
[Sideloadly](https://sideloadly.io/) or
[AltStore](https://altstore.io/) and install it onto the device.

## License

[MIT](LICENSE) © tkgstrator
