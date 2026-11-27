#!/bin/bash
# Clockpane.app をビルドする。
#   ./build.sh            → build/app.noindex/Clockpane.app を作成
#                            （名前の最後が .noindex のフォルダは Spotlight が無視するので、
#                              「アプリケーション」の Clockpane と二重に検索に出ない）
#   ./build.sh install    → さらに /Applications にコピーして起動
#   ./build.sh dmg        → さらに配布用の build/Clockpane-<版>.dmg を作成
# 版番号は環境変数 VERSION で指定できる（例：VERSION=1.0.0 ./build.sh dmg）。
# 指定がなければ Resources/Info.plist の値を使う。
set -euo pipefail
cd "$(dirname "$0")"

# Apple シリコンと Intel の両方で動く形（ユニバーサル）でビルドする
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Clockpane"

APP="build/app.noindex/Clockpane.app"
rm -rf "$APP" "build/Clockpane.app"   # 以前の置き場所に残っていれば消す
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp "Resources/Info.plist" "$APP/Contents/"

# 版番号を入れる
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-${VERSION}}" "$APP/Contents/Info.plist"
fi
VERSION_STRING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

# アイコンを作る（アプリ自身に描かせて .icns にする）
rm -rf "build/AppIcon.iconset"
"$BIN" --export-iconset "build/AppIcon.iconset"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "build/AppIcon.iconset"

# 署名なし配布のため、仮の署名（ad-hoc）だけを付ける
codesign --force --sign - "$APP" >/dev/null
echo "作成しました: ${PWD}/${APP}（版 ${VERSION_STRING}）"

case "${1:-}" in
install)
    DEST="/Applications"
    pkill -x Clockpane 2>/dev/null || true
    # 旧名「デスクトップ時計」(DesktopClock.app) が残っていれば終了して取り除く
    pkill -x DesktopClock 2>/dev/null || true
    rm -rf "$HOME/Applications/DesktopClock.app"
    # 以前の入れ先（~/Applications）のコピーは二重にならないよう取り除く
    rm -rf "$HOME/Applications/Clockpane.app"
    rm -rf "$DEST/Clockpane.app"
    cp -R "$APP" "$DEST/"
    echo "インストールしました: ${DEST}/Clockpane.app"
    open "$DEST/Clockpane.app"
    echo "起動しました"
    ;;
dmg)
    # 開くと「Clockpane」と「Applications」へのショートカットが並ぶ .dmg を作る
    DMG="build/Clockpane-${VERSION_STRING}.dmg"
    STAGE="build/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Clockpane ${VERSION_STRING}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    # GitHub の「いつも最新版」の URL で使う、版番号なしの名前のコピーも作る
    cp "$DMG" "build/Clockpane.dmg"
    echo "作成しました: ${PWD}/${DMG} と ${PWD}/build/Clockpane.dmg"
    ;;
esac
