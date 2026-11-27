import SwiftUI
import AppKit
import ServiceManagement

/// 2つ目に起動されたアプリから、動いている方へ「設定を開いて」と伝える合図
private let showSettingsNotification = Notification.Name("io.github.deskcraft.clockpane.showSettings")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var clockWindow: ClockWindowController?
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ログイン時の自動起動かどうか（自動起動のときは設定画面を出さない）
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedAsLoginItem = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // すでに別のコピーが動いていれば、そちらの設定画面を開いて自分は終了する
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                showSettingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        DistributedNotificationCenter.default().addObserver(
            forName: showSettingsNotification, object: nil, queue: .main) { _ in
            AppWindows.shared.showSettings()
        }

        // 「ログイン時に起動」を外から登録するためのモード（open --args --register-login-item）
        // 識別子を変えたあと、以前「ログイン時に起動」がオンだった場合も登録し直す
        let reRegister = UserDefaults.standard.bool(forKey: "reRegisterLoginItem")
        UserDefaults.standard.removeObject(forKey: "reRegisterLoginItem")
        if CommandLine.arguments.contains("--register-login-item") || reRegister {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set("enabled", forKey: "loginItemRegistration")
            } catch {
                UserDefaults.standard.set("error: \(error.localizedDescription)", forKey: "loginItemRegistration")
            }
        }

        NSApp.applicationIconImage = AppIcon.image(size: 512)
        AppWindows.shared.updateActivationPolicy()

        // アラーム・タイマー・時報・予定の見張りを始める
        AlertCenter.shared.setUpNotifications()
        Scheduler.shared.start()
        CalendarService.shared.requestAccessIfNeeded()
        // 動作確認用（open --args で指定したときだけ効く）
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--settings-tab"), i + 1 < args.count, let tab = SettingsTab(rawValue: args[i + 1]) {
            SettingsNavigation.shared.tab = tab
        }
        if args.contains("--test-preset-editor") {
            SettingsNavigation.shared.tab = .alarms
            AlarmSettingsView.openPresetEditorForTest = true
        }
        if args.contains("--test-quiet-alert") {
            // 音を出さない「静か」の知らせ方を一度だけ試す
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AlertCenter.shared.preview(FeatureSettings.shared.preset(AlertPreset.quietID).style,
                                           title: L("テスト", "Test"))
            }
        }
        if args.contains("--test-meeting-alert") {
            // 音を出さない知らせ方で、場所と会議リンクのある予定の知らせを試す
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AlertCenter.shared.fire(ActiveAlert(title: L("テスト会議", "Test Meeting"),
                                                    detail: L("あと5分で始まります", "Starts in 5 min"),
                                                    style: FeatureSettings.shared.preset(AlertPreset.quietID).style,
                                                    snoozeMinutes: nil,
                                                    location: L("会議室A", "Room A"),
                                                    link: URL(string: "https://zoom.us/j/0000000000")))
            }
        }
        if let i = args.firstIndex(of: "--test-timer-minutes"), i + 1 < args.count, let m = Int(args[i + 1]) {
            TimerModel.shared.startTimer(minutes: m)
        }
        clockWindow = ClockWindowController(settings: .shared)

        if !launchedAsLoginItem {
            AppWindows.shared.showSettings()
        }
    }

    /// 動いている最中に Finder や Dock からもう一度開かれたとき
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindows.shared.showSettings()
        return false
    }
}

@main
struct ClockpaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = ClockSettings.shared

    init() {
        // ビルド時にアイコン画像を書き出すためのモード（build.sh から使う）
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-iconset"), i + 1 < args.count {
            AppIcon.exportIconset(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
        // 確認用：全デザインを1枚の画像に書き出す
        if let i = args.firstIndex(of: "--export-design-sheet"), i + 1 < args.count {
            AppIcon.exportDesignSheet(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Clockpane", systemImage: "clock") {
            MenuContent(settings: settings)
        }
        .commands {
            // 画面上部の「Clockpane」メニュー
            CommandGroup(replacing: .appSettings) {
                Button(L("設定…", "Settings…")) { AppWindows.shared.showSettings() }
                    .keyboardShortcut(",")
            }
            // 「ファイル」メニュー：新規ウインドウなどは不要なので置き換え
            CommandGroup(replacing: .newItem) {
                Button(L("位置をリセット", "Reset Position")) {
                    NotificationCenter.default.post(name: .resetClockPosition, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            // 「表示」メニュー
            CommandMenu(L("時計", "Clock")) {
                Picker(L("時計の種類", "Clock Style"), selection: $settings.style) {
                    ForEach(ClockStyle.allCases) { Text($0.displayName).tag($0) }
                }
                Picker(L("デザイン", "Design"), selection: $settings.designID) {
                    ForEach(settings.orderedDesigns) { d in Text(settings.isFavorite(d.id) ? "★ \(d.name)" : d.name).tag(d.id) }
                }
                Button(L("選んでいるデザインをもとに新しく作る…", "New Design Based on Current…")) {
                    AppWindows.shared.createDesign(basedOn: settings.currentDesign)
                }
                .keyboardShortcut("n")
                Divider()
                Toggle(L("24時間表示", "24-Hour Time"), isOn: $settings.use24Hour)
                Toggle(L("秒を表示", "Show Seconds"), isOn: $settings.showSeconds)
                Toggle(L("曜日と日付", "Date and Weekday"), isOn: $settings.showDate)
                Divider()
                Toggle(L("常に手前に表示", "Always on Top"), isOn: $settings.alwaysOnTop)
                Toggle(L("ドラッグで時計を移動", "Drag to Move Clock"), isOn: $settings.dragEnabled)
            }
            // 「ヘルプ」メニュー
            CommandGroup(replacing: .help) {
                Button(L("Clockpane ヘルプ", "Clockpane Help")) { AppWindows.shared.showHelp() }
                    .keyboardShortcut("?")
            }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject private var alerts = AlertCenter.shared
    @ObservedObject private var timer = TimerModel.shared
    @ObservedObject private var fs = FeatureSettings.shared
    @ObservedObject private var calendar = CalendarService.shared

    var body: some View {
        if let alert = alerts.active {
            if let host = alert.linkHost {
                Button(L("会議に参加（\(host)）", "Join Meeting (\(host))")) { alerts.joinActive() }
            }
            Button(L("止める：\(alert.title)", "Stop: \(alert.title)")) { alerts.stop() }
            if let m = alert.snoozeMinutes {
                Button(L("スヌーズ（\(m)分）", "Snooze (\(m) min)")) { alerts.snooze() }
            }
            Divider()
        }

        if alerts.active?.link == nil, fs.calendarEnabled,
           let ev = calendar.nextEvent, let host = ev.linkHost {
            Button(L("次の予定に参加：\(ev.title)（\(host)）", "Join Next Event: \(ev.title) (\(host))")) {
                calendar.joinNextEvent()
            }
            Divider()
        }

        Button(L("設定を開く…", "Open Settings…")) { AppWindows.shared.showSettings() }
            .keyboardShortcut(",")
        Button(L("ヘルプ", "Help")) { AppWindows.shared.showHelp() }

        Divider()

        Menu(L("タイマー", "Timer")) {
            if let next = timer.waitingNextLabel {
                Button(next) { timer.startWaitingNext() }
                Button(L("ポモドーロを終える", "End Pomodoro")) { timer.stop() }
                Divider()
            }
            if timer.isRunning {
                if timer.isPaused {
                    Button(L("再開", "Resume")) { timer.resume() }
                } else {
                    Button(L("一時停止", "Pause")) { timer.pause() }
                }
                if timer.isPomodoro { Button(L("次へ進む", "Skip to Next")) { timer.skip() } }
                Button(L("止める", "Stop")) { timer.stop() }
                Divider()
            }
            ForEach(TimerPresets.minutes, id: \.self) { m in
                Button(TimerPresets.label(m)) { timer.startTimer(minutes: m) }
            }
            Divider()
            Button(L("ポモドーロを開始（作業\(fs.pomodoroWork)分）", "Start Pomodoro (\(fs.pomodoroWork)-min focus)")) { timer.startPomodoro() }
            Button(L("タイマーの設定…", "Timer Settings…")) { AppWindows.shared.showSettings(tab: .timer) }
        }
        Menu(L("アラーム", "Alarms")) {
            ForEach(fs.alarms) { alarm in
                Toggle("\(alarm.timeText)  \(alarm.displayLabel)（\(alarm.repeatSummary)）",
                       isOn: Binding(get: { alarm.enabled }, set: { fs.setAlarm(alarm.id, enabled: $0) }))
            }
            if !fs.alarms.isEmpty { Divider() }
            Button(L("アラームを追加・編集…", "Add or Edit Alarms…")) { AppWindows.shared.showSettings(tab: .alarms) }
        }

        Divider()

        Picker(L("表示", "Style"), selection: $settings.style) {
            ForEach(ClockStyle.allCases) { Text($0.displayName).tag($0) }
        }
        Picker(L("デザイン", "Design"), selection: $settings.designID) {
            ForEach(settings.orderedDesigns) { d in Text(settings.isFavorite(d.id) ? "★ \(d.name)" : d.name).tag(d.id) }
        }
        Toggle(L("24時間表示", "24-Hour Time"), isOn: $settings.use24Hour)
        Toggle(L("常に手前に表示", "Always on Top"), isOn: $settings.alwaysOnTop)
        Toggle(L("ドラッグで時計を移動", "Drag to Move Clock"), isOn: $settings.dragEnabled)
        Button(L("位置をリセット", "Reset Position")) {
            NotificationCenter.default.post(name: .resetClockPosition, object: nil)
        }

        Divider()

        Button(L("終了", "Quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
