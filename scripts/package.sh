#!/usr/bin/env bash
#
# 打发布包：同时产出 .zip 和 .dmg
#
#   ./scripts/package.sh 1.0.0
#
# 默认打通用二进制（Intel + Apple Silicon）。只想要本机架构：
#   UNIVERSAL=0 ./scripts/package.sh 1.0.0
#
set -euo pipefail

NAME="LayoutSnap"
VERSION="${1:-1.0.0}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$ROOT/build/$NAME.app"

export UNIVERSAL="${UNIVERSAL:-1}"
export VERSION

echo "==> 打包 $NAME ${VERSION}（UNIVERSAL=${UNIVERSAL}）"
"$ROOT/scripts/build.sh" release

rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> 生成 zip"
# 用 ditto 而不是 zip：能正确保留符号链接、权限和扩展属性
ditto -c -k --keepParent "$APP" "$DIST/$NAME-$VERSION.zip"

echo "==> 生成 dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$NAME-$VERSION.dmg"
if hdiutil create -volname "$NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
  echo "    ok"
else
  rm -f "$DMG"
  if [ "${REQUIRE_DMG:-0}" = "1" ]; then
    echo "    dmg 制作失败（REQUIRE_DMG=1，中止）" >&2
    exit 1
  fi
  echo "    dmg 制作失败（某些受限环境不允许挂载磁盘镜像），这次只出 zip"
fi
rm -rf "$STAGE"

echo "==> 校验"
lipo -archs "$APP/Contents/MacOS/$NAME" || true
codesign --verify --verbose "$APP" 2>&1 | tail -2 || true

echo "==> 产物"
ls -lh "$DIST"
