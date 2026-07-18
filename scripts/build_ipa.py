#!/usr/bin/env python3
"""Inject a tweak dylib into a decrypted IPA and repack.

Usage:
    build_ipa.py --input <base.ipa> --dylib <tweak.dylib> --output <out.ipa>

Steps:
    1. Extract the base IPA (must be a fairplay-decrypted copy — App Store
       IPAs won't run under a load-command edit until the FairPlay
       encryption is stripped).
    2. Locate Payload/*.app and its CFBundleExecutable.
    3. Add LC_LOAD_DYLIB @rpath/<dylib> to the app binary via LIEF.
    4. Drop the dylib into Payload/*.app/Frameworks/.
    5. Zip everything back into an IPA. TrollStore / TrollStore Lite
       accepts unsigned or fake-signed IPAs, so no codesign step here.
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import lief


def inject_load_dylib(binary_path: Path, dylib_name: str) -> None:
    """Add LC_LOAD_DYLIB @rpath/<dylib_name> to every Mach-O slice."""
    fat = lief.MachO.parse(str(binary_path))
    if fat is None:
        raise RuntimeError(f"LIEF failed to parse {binary_path}")

    load_path = f"@rpath/{dylib_name}"
    for macho in fat:
        # Skip if the load command is already there (idempotent re-runs).
        already = any(
            getattr(cmd, "name", None) == load_path
            for cmd in macho.commands
        )
        if already:
            continue
        macho.add(lief.MachO.DylibCommand.load_dylib(load_path))

    fat.write(str(binary_path))


def repack_ipa(root: Path, out_ipa: Path) -> None:
    """Zip `root` (containing Payload/) into out_ipa, dropping metadata."""
    out_ipa.parent.mkdir(parents=True, exist_ok=True)
    if out_ipa.exists():
        out_ipa.unlink()
    with zipfile.ZipFile(out_ipa, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(root.rglob("*")):
            rel = path.relative_to(root)
            if path.is_file() or path.is_symlink():
                z.write(path, rel)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, type=Path, help="decrypted base IPA")
    ap.add_argument("--dylib", required=True, type=Path, help="tweak dylib to inject")
    ap.add_argument("--output", required=True, type=Path, help="patched IPA output path")
    args = ap.parse_args()

    if not args.input.is_file():
        print(f"error: input IPA not found: {args.input}", file=sys.stderr)
        return 1
    if not args.dylib.is_file():
        print(f"error: dylib not found: {args.dylib}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        with zipfile.ZipFile(args.input) as z:
            z.extractall(tmp)

        payload = tmp / "Payload"
        app_dirs = list(payload.glob("*.app"))
        if not app_dirs:
            print(f"error: no *.app under Payload/ in {args.input}", file=sys.stderr)
            return 1
        app_dir = app_dirs[0]

        with (app_dir / "Info.plist").open("rb") as f:
            info = plistlib.load(f)
        binary_name = info["CFBundleExecutable"]
        binary_path = app_dir / binary_name

        frameworks = app_dir / "Frameworks"
        frameworks.mkdir(exist_ok=True)
        shutil.copy2(args.dylib, frameworks / args.dylib.name)

        inject_load_dylib(binary_path, args.dylib.name)

        repack_ipa(tmp, args.output)

    print(f"==> wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
