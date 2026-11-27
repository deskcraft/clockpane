import SwiftUI

struct HelpView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let lines: [String]
    }

    /// 言語を切り替えたときに作り直すため、設定を見張る
    @ObservedObject private var settings = ClockSettings.shared

    private var topics: [Topic] { [
        Topic(title: L("はじめに", "Getting Started"), symbol: "clock", lines: [
            L("Clockpane は、デスクトップ（ウインドウの裏）に時計を表示するアプリです。", "Clockpane shows a clock on your desktop (behind your windows)."),
            L("起動すると、画面右上のメニューバーに時計のアイコンが出ます。", "When it’s running, a clock icon appears in the menu bar at the top right of the screen."),
            L("Dock にもアイコンが出ます。Dock のアイコンを右クリック →「オプション」→「Dockに追加」で固定できます。", "Its icon also appears in the Dock. Right-click the Dock icon → Options → Keep in Dock to pin it."),
            L("設定の「Dockにアイコンを表示」をオフにすると、設定画面とヘルプを閉じたあとはメニューバーのアイコンだけになります（時計は動き続けます）。", "If you turn off “Show Icon in Dock”, only the menu bar icon remains after you close Settings and Help (the clock keeps running)."),
        ]),
        Topic(title: L("画面上部のメニュー", "Menus at the Top of the Screen"), symbol: "menubar.rectangle", lines: [
            L("「Clockpane」：このアプリについて、設定…（⌘,）、非表示（⌘H）、終了（⌘Q）", "“Clockpane”: About, Settings… (⌘,), Hide (⌘H), Quit (⌘Q)"),
            L("「ファイル」：位置をリセット（⇧⌘R）、閉じる（⌘W）", "“File”: Reset Position (⇧⌘R), Close (⌘W)"),
            L("「時計」：時計の種類、デザイン、24時間表示、秒、曜日と日付、常に手前に表示、ドラッグで移動", "“Clock”: style, design, 24-hour time, seconds, date and weekday, always on top, drag to move"),
            L("「ヘルプ」：このヘルプ（⌘?）", "“Help”: this help (⌘?)"),
        ]),
        Topic(title: L("設定画面を開く", "Opening Settings"), symbol: "gearshape", lines: [
            L("アプリをダブルクリックする", "Double-click the app"),
            L("メニューバーの時計アイコン →「設定を開く…」", "Menu bar clock icon → Open Settings…"),
            L("設定画面が開いている間は、画面上部の「Clockpane」メニュー →「設定…」（⌘,）", "While Settings is open: “Clockpane” menu at the top of the screen → Settings… (⌘,)"),
        ]),
        Topic(title: L("表示の切り替え", "Display Options"), symbol: "switch.2", lines: [
            L("時計の種類：アナログとデジタルを切り替えます。", "Clock style: switch between analog and digital."),
            L("24時間表示：オフにすると「午前／午後」付きの12時間表示になります（デジタルのみ）。", "24-Hour Time: turn off for 12-hour time with AM/PM (digital only)."),
            L("秒針・曜日と日付：表示するかどうかを選べます。", "Second hand, date and weekday: choose whether to show them."),
            L("デザイン：標準の16種類と、自分で作ったデザインから選べます。", "Design: choose from 16 built-in designs or your own."),
            L("お気に入り：デザインの右上の☆をクリックすると、一覧とメニューの先頭に表示されます。もう一度クリックで外れます。", "Favorites: click ☆ at the top right of a design to show it first in the list and menus. Click again to remove it."),
            L("サイズ・不透明度：スライダーで調整します。", "Size and opacity: adjust with the sliders."),
            L("言語：設定画面の「一般」→「言語」で、システムに合わせる・日本語・English を選べます。日付と曜日の表記も切り替わります。",
              "Language: choose Match System, 日本語, or English in Settings → General → Language. The date and weekday format changes too."),
        ]),
        Topic(title: L("自分でデザインを作る", "Creating Your Own Design"), symbol: "paintpalette", lines: [
            L("設定画面の「選んでいるデザインをもとに新しく作る…」、デザインの右クリック →「これをもとに新しく作る…」、または「時計」メニュー（⌘N）で編集画面が開きます。", "Open the editor with “New Design Based on Current…” in Settings, by right-clicking a design → “New Design Based on This…”, or from the “Clock” menu (⌘N)."),
            L("縁（太さ・色・点の飾り）、盤面の色、目盛り、数字（種類・書体・色・大きさ・位置）、針（色・形・太さ）、秒の表し方、日付・曜日（内容・位置・色）を変えられます。", "You can change the rim (thickness, colors, dotted ring), face colors, marks, numbers (type, typeface, color, size, position), hands (color, shape, thickness), seconds display, and date and weekday (content, position, color)."),
            L("左のプレビューで確かめてから「保存して使う」を押すと、名前を付けて一覧に追加され、すぐに使われます。", "Check the preview on the left, then click “Save and Use” to add it to the list under its name and use it right away."),
            L("自分で作ったデザインは、右クリックで編集・複製・削除ができます。", "Right-click your own designs to edit, duplicate, or delete them."),
        ]),
        Topic(title: L("時計の位置", "Clock Position"), symbol: "arrow.up.and.down.and.arrow.left.and.right", lines: [
            L("時計の中心にマウスを乗せると丸いつまみが出ます。つまみをクリック（または右クリック）すると、その場にメニューが出ます（設定、デザイン、表示の切り替え、終了など）。", "Hover over the center of the clock to show a round handle. Click (or right-click) the handle to open a menu right there (settings, design, display options, quit, and more)."),
            L("「ドラッグで時計を移動」をオンにすると時計が手前に出て、つまみをドラッグして動かせます。", "Turn on “Drag to Move Clock” to bring the clock to the front and drag the handle to move it."),
            L("つまみ以外の場所のクリックは、時計を素通りして下のウインドウに届きます。", "Clicks anywhere other than the handle pass through the clock to the window below."),
            L("「常に手前に表示」をオンにすると、ほかのウインドウより手前に出ます。クリックは時計を素通りします。", "Turn on “Always on Top” to show the clock above other windows. Clicks pass through the clock."),
            L("時計が見当たらないときは「位置をリセット」で画面右上に戻せます。", "If you can’t find the clock, use “Reset Position” to move it back to the top right of the screen."),
        ]),
        Topic(title: L("ログイン時に起動", "Open at Login"), symbol: "power", lines: [
            L("設定画面の「一般」→「ログイン時に起動」をオンにすると、Mac にログインしたときに自動で時計が出ます。", "Turn on Settings → General → “Open at Login” to show the clock automatically when you log in to your Mac."),
            L("アプリをアプリケーションフォルダ（/Applications）に置いてから設定してください。", "Put the app in the Applications folder (/Applications) before turning this on."),
        ]),
        Topic(title: L("アラーム", "Alarms"), symbol: "alarm", lines: [
            L("設定画面の「アラーム」で追加します。時刻・名前・繰り返し（1回だけ／毎日／平日／曜日を選ぶ）・知らせ方・スヌーズの分数を決められます。",
              "Add alarms in Settings → Alarms. Set the time, name, repeat (once, every day, weekdays, or chosen days), alert style, and snooze length."),
            L("知らせている間は時計のどこをクリックしても止まります。時計の中心やメニューバーのメニューから「スヌーズ」もできます。",
              "While an alert is showing, click anywhere on the clock to stop it. Snooze from the clock’s center menu or the menu bar."),
            L("Mac がスリープしている間は鳴りません。戻ったときに「鳴らなかったアラーム」として知らせます。",
              "Alarms can’t ring while the Mac is asleep; missed alarms are reported when it wakes up."),
        ]),
        Topic(title: L("知らせ方とお気に入り", "Alert Styles and Favorites"), symbol: "bell.badge", lines: [
            L("知らせ方では、時計での表示（光る・点滅・拡大・名前）、音（種類・音量・回数）、通知センター、読み上げ、自動で止めるまでの時間を選べます。",
              "An alert style sets how the clock looks (glow, blink, enlarge, name), the sound (type, volume, repeats), Notification Center, speech, and when to stop automatically."),
            L("最初から「標準（推奨）」「静か（表示だけ）」「しっかり」が入っています。「複製して編集」や「知らせ方を追加」で自分用を作り、☆でお気に入りにすると一覧の先頭に出ます。",
              "Standard (Recommended), Quiet, and Strong are built in. Create your own with “Duplicate and Edit” or “Add Alert Style”, and click ☆ to list favorites first."),
        ]),
        Topic(title: L("タイマー・ポモドーロ・時報", "Timer, Pomodoro and Chime"), symbol: "timer", lines: [
            L("時計の中心のメニュー →「タイマー」、メニューバーのメニュー、または設定画面の「タイマー・時報」で開始します。",
              "Start a timer from the clock’s center menu → Timer, the menu bar menu, or Settings → Timer & Chime."),
            L("動いている間は、アナログ時計の縁に残りの時間が輪で、時計の下に残り時間が出ます。",
              "While running, the remaining time appears as a ring on the analog clock and as text below the clock."),
            L("ポモドーロは作業と休憩を交互にくり返します。時報は毎正時か30分ごとに小さく鳴らし、夜は鳴らさない設定もできます。",
              "Pomodoro alternates focus and break sessions. The chime sounds every hour or half hour, with an option to stay quiet at night."),
        ]),
        Topic(title: L("予定・世界時計・締切", "Calendar, World Clock and Deadlines"), symbol: "calendar", lines: [
            L("設定画面の「予定・世界時計」で、Mac のカレンダーの次の予定を時計の下に表示し、始まる前に知らせることができます（最初にカレンダーへのアクセスの許可が必要です）。",
              "In Settings → Calendar & World, show the next event from the Mac’s Calendar below the clock and get alerted before it starts (calendar access must be allowed first)."),
            L("予定に場所や会議のリンク（Zoom・Teams・Google Meet・Webex など）があれば、時計の下と知らせに「📍 場所　🔗 zoom.us」のように出ます。通知の「参加する」、知らせている時計の右クリック、時計の中心やメニューバーの「次の予定に参加」で、リンクを開けます。",
              "If an event has a location or a meeting link (Zoom, Teams, Google Meet, Webex, and more), it appears below the clock and in the alert, like “📍 Room A  🔗 zoom.us”. Open the link with Join in the notification, by right-clicking the clock during the alert, or with “Join Next Event” in the clock’s center menu or the menu bar."),
            L("世界時計は、ほかの都市の時刻を4つまで時計の下に表示します。締切は、一番近いものを「あと○日」と表示します。",
              "The world clock shows up to 4 other cities below the clock. Deadlines show the nearest one as “in N days”."),
        ]),
        Topic(title: L("終了する", "Quitting"), symbol: "xmark.circle", lines: [
            L("メニューバーの時計アイコン →「終了」、または設定画面が開いている間に ⌘Q。", "Menu bar clock icon → Quit, or ⌘Q while Settings is open."),
        ]),
    ] }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Clockpane ヘルプ", "Clockpane Help")).font(.title2.bold())
                        Text(L("バージョン \(version)", "Version \(version)"))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(topics, id: \.title) { topic in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(topic.title, systemImage: topic.symbol)
                            .font(.headline)
                        ForEach(topic.lines, id: \.self) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(line).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(L("ウェブサイト・アップデート", "Website and Updates"), systemImage: "globe")
                        .font(.headline)
                    AboutLinksView()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 600)
    }
}
