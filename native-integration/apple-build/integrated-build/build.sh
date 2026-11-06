#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
[[ $(uname -s) == Darwin ]] || exit 1
ROOT=$(cd ../.. && pwd)
OUT="$PWD/out"
mkdir -p "$OUT/source"
exec > >(tee "$OUT/build.log") 2>&1
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CLANG=$(xcrun --sdk iphoneos --find clang)
{ sw_vers; xcodebuild -version; "$CLANG" --version; xcrun ld -v 2>&1; echo "SDK=$SDK"; } > "$OUT/toolchain.txt"
python3 manifest.py "$ROOT" "$OUT" 
for arch in arm64 arm64e; do
  flags=(-target "$arch-apple-ios15.0" -isysroot "$SDK" -fblocks -fobjc-exceptions -O2 -Wall -Wextra -Werror -Wno-deprecated-declarations -I"$ROOT/own-assets-staging-v3")
  "$CLANG" "${flags[@]}" -fno-objc-arc -E "$ROOT/NahidaCompat.m" -o "$OUT/NahidaCompat.$arch.i"
  python3 verify.py --pin "$OUT/NahidaCompat.$arch.i"
  "$CLANG" "${flags[@]}" -fno-objc-arc -c "$ROOT/NahidaCompat.m" -o "$OUT/NahidaCompat.$arch.o"
  "$CLANG" "${flags[@]}" -fobjc-arc -c "$ROOT/state-variants-impl/NativeStateVariants.m" -o "$OUT/NativeStateVariants.$arch.o"
  "$CLANG" "${flags[@]}" -v -dynamiclib "$OUT/NahidaCompat.$arch.o" "$OUT/NativeStateVariants.$arch.o" -Wl,-undefined,error -framework Foundation -framework CoreFoundation -lobjc -install_name @rpath/NahidaCompat.dylib -o "$OUT/NahidaCompat.$arch.dylib"
  xcrun otool -hv "$OUT/NahidaCompat.$arch.o" "$OUT/NativeStateVariants.$arch.o" "$OUT/NahidaCompat.$arch.dylib"
  xcrun otool -L "$OUT/NahidaCompat.$arch.dylib"
  xcrun nm -u "$OUT/NahidaCompat.$arch.dylib" > "$OUT/undefined.$arch.txt"
done
xcrun lipo -create "$OUT/NahidaCompat.arm64.dylib" "$OUT/NahidaCompat.arm64e.dylib" -output "$OUT/NahidaCompat.dylib"
xcrun lipo -info "$OUT/NahidaCompat.dylib"
python3 verify.py "$OUT" | tee "$OUT/verification.json"
(cd "$OUT" && shasum -a 256 *.o *.dylib *.i *.json toolchain.txt undefined.*.txt > SHA256SUMS)
