#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ "$(uname -s)" == Darwin ]] || { echo 'ERROR: Apple macOS toolchain required, no lld fallback.' >&2; exit 1; }
OUT="${OUT:-$PWD/out}"
mkdir -p "$OUT"
exec > >(tee "$OUT/build.log") 2>&1
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CLANG="$(xcrun --sdk iphoneos --find clang)"
LD="$(xcrun --sdk iphoneos --find ld)"
LIPO="$(xcrun --find lipo)"
{
  sw_vers
  xcodebuild -version
  "$CLANG" --version
  "$LD" -v 2>&1 || true
  printf 'SDK=%s\nCLANG=%s\nLD=%s\n' "$SDK" "$CLANG" "$LD"
  shasum -a 256 ../NahidaCompat.m build_apple.sh verify_macho.py
} | tee "$OUT/toolchain.txt"
for arch in arm64 arm64e; do
  common=(-target "$arch-apple-ios15.0" -isysroot "$SDK" -fno-objc-arc -fblocks -fobjc-exceptions -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations)
  "$CLANG" "${common[@]}" -c ../NahidaCompat.m -o "$OUT/NahidaCompat.$arch.o"
  # Driver's native Apple linker, no -fuse-ld=lld or header manipulation.
  "$CLANG" "${common[@]}" -v -dynamiclib "$OUT/NahidaCompat.$arch.o" \
    -framework Foundation -framework CoreFoundation -lobjc \
    -install_name @rpath/NahidaCompat.dylib -o "$OUT/NahidaCompat.$arch.dylib"
  xcrun otool -hv "$OUT/NahidaCompat.$arch.o" "$OUT/NahidaCompat.$arch.dylib"
  xcrun otool -L "$OUT/NahidaCompat.$arch.dylib"
done
"$LIPO" -create "$OUT/NahidaCompat.arm64.dylib" "$OUT/NahidaCompat.arm64e.dylib" -output "$OUT/NahidaCompat.dylib"
"$LIPO" -info "$OUT/NahidaCompat.dylib"
xcrun otool -arch all -hv "$OUT/NahidaCompat.dylib"
python3 verify_macho.py "$OUT" | tee "$OUT/verification.json"
(cd "$OUT" && shasum -a 256 NahidaCompat.* toolchain.txt verification.json > SHA256SUMS)
echo 'Static cross-build and CPU subtype verification only; not device/runtime validation.'
