# Clockpane 開発メモ

## ビルドと起動

必要なもの：macOS 15 以降、Xcode（Swift 6 のツールチェーン）。

```bash
./build.sh            # build/Clockpane.app を作成
./build.sh install    # さらに /Applications にコピーして起動
./build.sh dmg        # さらに配布用の build/Clockpane-<版>.dmg と build/Clockpane.dmg を作成
VERSION=1.2.0 ./build.sh dmg   # 版番号を指定して作る
```

Xcode で開く場合は `Package.swift` を開きます。

## リリースの出し方

版のタグを送ると、GitHub Actions（`.github/workflows/release.yml`）が macOS でビルドし、
.dmg を Releases に置きます。

```bash
git tag v1.0.1
git push origin v1.0.1
```

- `Clockpane.dmg`（版番号なし）は、いつも最新版を指す URL
  `https://github.com/deskcraft/clockpane/releases/latest/download/Clockpane.dmg` で使います。
- Apple の署名（Developer ID）と公証はしていません。仮の署名（ad-hoc）だけです。

## 設計の要点

- 画面の文字は `L("日本語", "English")` で書いています（`ClockSettings.swift` の `L` 関数）。
- 標準デザインはすべてコードで描いた独自のもので、外部の画像・ロゴ・文字は使っていません。
- 時計のウインドウはクリックを素通りさせ、時計の中心のつまみの上にマウスがあるときだけクリックを受け取ります
  （ウインドウ単位でしか切り替えられないため、30 回/秒マウスの位置を見ています）。
- 位置は「時計の中心」で保存します。時計の下の情報欄が出入りしてウインドウの大きさが変わっても、
  利用者が置いた位置（anchor）を基準にするため、画面の端で押し戻されても元に戻ります。
- 保存データ（アラーム・知らせ方・自作デザインなど）は 1 件ずつ読み込み、読めない 1 件だけを読み飛ばします。
  項目が足りない古い形式のデータは、初期値で補います（時刻が読めないアラームは読み飛ばします）。
- 知らせが重なったときは順番待ちにし、1 つずつ知らせます。通知センターのボタンは、押した通知の知らせにだけ効きます。
- 識別子は `io.github.deskcraft.clockpane` です。以前の `local.clockpane.Clockpane` の設定は、最初の起動時に一度だけ引き継ぎます。

## 動作確認用の起動オプション

`open /Applications/Clockpane.app --args …` で指定します。

| オプション | 内容 |
|---|---|
| `--settings-tab clock\|design\|alarms\|timer\|more\|general` | その項目を開いた状態で設定画面を出す |
| `--test-quiet-alert` | 音なしの知らせ方を一度試す |
| `--test-meeting-alert` | 音なしで、場所と会議リンク付きの知らせを試す |
| `--test-timer-minutes N` | N 分のタイマーを始める |
| `--test-preset-editor` | 知らせ方の編集画面を開く |
| `--export-design-sheet <path>` | 全デザインを並べた画像を書き出して終了する |
| `--export-iconset <dir>` | アイコンの画像を書き出して終了する（build.sh が使う） |

## ファイル構成

| ファイル | 内容 |
|---|---|
| `Sources/Clockpane/ClockpaneApp.swift` | アプリ本体、メニューバーのメニュー |
| `Sources/Clockpane/ClockSettings.swift` | 時計の設定の保存、表示言語、設定の引き継ぎ |
| `Sources/Clockpane/ClockDesign.swift` | デザインの色・形の定義（ここに追加すれば新デザイン） |
| `Sources/Clockpane/ClockViews.swift` | アナログ・デジタル時計の描画、日付の書式 |
| `Sources/Clockpane/ClockWindowController.swift` | デスクトップ上の透明ウインドウ、中心のつまみとメニュー |
| `Sources/Clockpane/SettingsView.swift` | 設定画面（時計・デザイン・一般） |
| `Sources/Clockpane/FeatureSettingsViews.swift` | 設定画面（アラーム・タイマー・時報・予定・世界時計） |
| `Sources/Clockpane/SettingsWindowController.swift` | 設定・ヘルプ・デザイン編集のウインドウ |
| `Sources/Clockpane/DesignEditorView.swift` | デザインの編集画面 |
| `Sources/Clockpane/Features.swift` | アラーム・知らせ方・タイマー・時報・世界時計・締切の設定と保存 |
| `Sources/Clockpane/AlertCenter.swift` | 知らせる処理（音・読み上げ・通知センター・スヌーズ・順番待ち） |
| `Sources/Clockpane/Scheduler.swift` | 毎秒の見張り（アラーム・タイマー・ポモドーロ・時報）と時計の下の情報欄 |
| `Sources/Clockpane/CalendarService.swift` | Mac のカレンダーから予定を読む、会議リンクを探す |
| `Sources/Clockpane/InfoViews.swift` | 知らせているときの表示・タイマーの輪・時計の下の情報欄 |
| `Sources/Clockpane/HelpView.swift` | ヘルプ画面 |
| `Sources/Clockpane/AppIcon.swift` | アプリのアイコン（コードで描画） |
