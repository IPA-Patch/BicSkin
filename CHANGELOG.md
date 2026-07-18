# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The section that matches a pushed `v*.*.*` tag is extracted verbatim by
`.github/workflows/deployment.yaml` and posted as the GitHub Release body,
so keep each `## [X.Y.Z]` heading in the exact form the workflow greps for.

## [Unreleased]

## [0.1.0] - 2026-07-19

### Added

- Point-card face swap on `BicCamera` (`com.biccamera.ios.mobile.BicCamera`):
  double-tap the card image to cycle between BicCamera's bundled
  `pointcard_default` watermark and the *Bicame Musume* (ビッカメ娘)
  collaboration design pulled from BicCamera's CDN.
- Toggle position is persisted to `NSUserDefaults` (integer index, not a
  boolean) so additional card designs can be appended to the pool without
  breaking any user's saved preference, and each launch restores the last
  face automatically.
- Manual `CATransform3D` Y-axis flip animation that preserves the card's
  16 pt rounded corners throughout — `UIViewAnimationOptionTransitionFlip*`
  drops the layer mask mid-flip, so BicSkin walks the superview chain to
  the deepest `cornerRadius > 0` ancestor and rotates its layer directly.
- Debug-only `NSJSONSerialization` swizzle that rewrites the point-card
  profile response with dummy card number / barcode / balance / expiry —
  used solely to keep real values out of the screenshots and demo video
  in `README.md`. Compiled out entirely by `FINALPACKAGE=1`.
- Process-wide install marker (associated object on `UIImageView`, keyed
  by a process-interned `SEL`) so the Substrate `.deb` and a jailed-IPA
  embed can co-exist in the same process without their `bic_init`
  constructors cancelling each other's `method_exchangeImplementations`.
- CI: commit-lint / Theos debug build on every non-master push and PR
  (`.github/workflows/integration.yaml`).
- Release: tag-driven Theos `FINALPACKAGE=1` `.deb` build published as a
  GitHub Release with SHA256 checksums
  (`.github/workflows/deployment.yaml`, triggers on `v*.*.*`).

[Unreleased]: https://github.com/IPA-Patch/BicSkin/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/IPA-Patch/BicSkin/releases/tag/v0.1.0
