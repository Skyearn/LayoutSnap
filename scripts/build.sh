#!/usr/bin/env bash
#
# 把 swift build 出来的可执行文件包成一个正经的 .app
#
#   ./scripts/build.sh            # release 构建 + 打包
#   ./scripts/build.sh debug      # debug 构建
#   ./scripts/build.sh release install   # 打包后复制到 /Applications
#
set -euo pipefail

NAME="LayoutSnap"
BUNDLE_ID="com.skyearn.layoutsnap"
CONFIG="${1:-release}"
ACTION="${2:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/$NAME.app"
CACHE="$ROOT/.build/cache"
mkdir -p "$CACHE"
export CLANG_MODULE_CACHE_PATH="$CACHE"

SWIFT_ARGS=(--disable-sandbox --cache-path "$CACHE" --scratch-path "$ROOT/.build")

# 发布版打成通用二进制（Intel + Apple Silicon 都能跑）：
#   UNIVERSAL=1 ./scripts/build.sh release
if [ "${UNIVERSAL:-0}" = "1" ]; then
  SWIFT_ARGS+=(--arch arm64 --arch x86_64)
  echo "==> 编译通用二进制 ($CONFIG, arm64 + x86_64)"
else
  echo "==> 编译 ($CONFIG)"
fi
swift build -c "$CONFIG" "${SWIFT_ARGS[@]}"

BIN_DIR="$(swift build -c "$CONFIG" "${SWIFT_ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/$NAME"
if [ ! -f "$BIN" ]; then
  echo "找不到可执行文件: $BIN" >&2
  exit 1
fi

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 版本号必须在签名之前写进 Info.plist，签完再改会破坏签名
if [ -n "${VERSION:-}" ]; then
  echo "==> 写入版本号 $VERSION"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# 本地化显示名（中文系统里显示「布局快照」，其他语言回退 LayoutSnap）
for lproj in "$ROOT/Resources"/*.lproj; do
  [ -d "$lproj" ] || continue
  cp -R "$lproj" "$APP/Contents/Resources/"
done

# 辅助功能授权是按「签名 + bundle id」记的。用 ad-hoc 签名的话，
# 每次重新编译二进制变化，授权就可能失效；所以优先用本机证书签。
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | head -1 || true)"
fi

if [ -n "${IDENTITY:-}" ]; then
  echo "==> 签名（${IDENTITY}）"
  codesign --force --deep --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || {
    echo "    签名失败，退回 ad-hoc"
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  }
else
  echo "==> ad-hoc 签名"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

codesign --verify --verbose "$APP" 2>&1 | tail -2 || true

if [ "$ACTION" = "install" ]; then
  echo "==> 安装到 /Applications"
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/$NAME.app"
  echo "    完成：/Applications/$NAME.app"
fi

echo "==> 完成：$APP"
echo "    双击打开，或者：open \"$APP\""
echo "    （首次运行请到 系统设置 › 隐私与安全性 › 辅助功能 里勾选 ${NAME}，然后重启应用）"
