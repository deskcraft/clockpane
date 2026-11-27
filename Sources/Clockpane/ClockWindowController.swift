import AppKit
import SwiftUI
import Combine

/// 時計の中心のつまみの操作を受け取るホスティングビュー
/// - クリック（動かさずに離す）・右クリック：メニューを出す
/// - ドラッグ：「ドラッグで時計を移動」がオンのときだけ時計を動かす
/// - 知らせている間：どこをクリックしても止める（右クリックはメニュー）
final class ClockHostingView<Content: View>: NSHostingView<Content> {
    var canDrag: () -> Bool = { false }
    var showMenu: (NSEvent, NSView) -> Void = { _, _ in }
    var isAlerting: () -> Bool = { false }
    var stopAlert: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        if isAlerting() { stopAlert(); return }
        guard let window else { return }
        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        var moved = false
        // ボタンを離すまで追いかけ、3pt 以上動いたらドラッグ、動かなければクリック
        while let e = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            let now = NSEvent.mouseLocation
            let dx = now.x - startMouse.x, dy = now.y - startMouse.y
            if !moved && hypot(dx, dy) < 3 { continue }
            guard canDrag() else { continue }
            moved = true
            window.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
        if !moved { showMenu(event, self) }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu(event, self)
    }

    override var acceptsFirstResponder: Bool { false }
}

/// 押すと決まった処理を行うメニュー項目
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// 時計の中心をクリックしたときに出すメニュー（メニューバーのアイコンのメニューと同じ内容）
enum ClockPopupMenu {
    static func make(_ s: ClockSettings) -> NSMenu {
        let menu = NSMenu()

        // 知らせている間は、止める・スヌーズを先頭に
        if let alert = AlertCenter.shared.active {
            if let host = alert.linkHost {
                menu.addItem(ClosureMenuItem(L("会議に参加（\(host)）", "Join Meeting (\(host))")) { AlertCenter.shared.joinActive() })
            }
            menu.addItem(ClosureMenuItem(L("止める：\(alert.title)", "Stop: \(alert.title)")) { AlertCenter.shared.stop() })
            if let m = alert.snoozeMinutes {
                menu.addItem(ClosureMenuItem(L("スヌーズ（\(m)分）", "Snooze (\(m) min)")) { AlertCenter.shared.snooze() })
            }
            menu.addItem(.separator())
        }

        // 次の予定に会議のリンクがあれば、すぐ参加できるように
        if AlertCenter.shared.active?.link == nil, FeatureSettings.shared.calendarEnabled,
           let ev = CalendarService.shared.nextEvent, let host = ev.linkHost {
            menu.addItem(ClosureMenuItem(L("次の予定に参加：\(ev.title)（\(host)）", "Join Next Event: \(ev.title) (\(host))")) {
                CalendarService.shared.joinNextEvent()
            })
            menu.addItem(.separator())
        }

        menu.addItem(ClosureMenuItem(L("設定を開く…", "Open Settings…")) { AppWindows.shared.showSettings() })
        menu.addItem(ClosureMenuItem(L("ヘルプ", "Help")) { AppWindows.shared.showHelp() })
        menu.addItem(.separator())

        menu.addItem(submenu(L("タイマー", "Timer"), timerMenu()))
        menu.addItem(submenu(L("アラーム", "Alarms"), alarmMenu()))
        menu.addItem(.separator())

        let styleMenu = NSMenu()
        for style in ClockStyle.allCases {
            styleMenu.addItem(ClosureMenuItem(style.displayName, checked: s.style == style) { s.style = style })
        }
        menu.addItem(submenu(L("表示", "Style"), styleMenu))

        let designMenu = NSMenu()
        for d in s.orderedDesigns {
            let title = s.isFavorite(d.id) ? "★ \(d.name)" : d.name
            designMenu.addItem(ClosureMenuItem(title, checked: s.designID == d.id) { s.designID = d.id })
        }
        designMenu.addItem(.separator())
        designMenu.addItem(ClosureMenuItem(L("選んでいるデザインをもとに新しく作る…", "New Design Based on Current…")) {
            AppWindows.shared.createDesign(basedOn: s.currentDesign)
        })
        menu.addItem(submenu(L("デザイン", "Design"), designMenu))

        menu.addItem(ClosureMenuItem(L("24時間表示", "24-Hour Time"), checked: s.use24Hour) { s.use24Hour.toggle() })
        menu.addItem(ClosureMenuItem(s.style == .analog ? L("秒針", "Second Hand") : L("秒を表示", "Show Seconds"), checked: s.showSeconds) { s.showSeconds.toggle() })
        menu.addItem(ClosureMenuItem(L("曜日と日付", "Date and Weekday"), checked: s.showDate) { s.showDate.toggle() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("常に手前に表示", "Always on Top"), checked: s.alwaysOnTop) { s.alwaysOnTop.toggle() })
        menu.addItem(ClosureMenuItem(L("ドラッグで時計を移動", "Drag to Move Clock"), checked: s.dragEnabled) { s.dragEnabled.toggle() })
        menu.addItem(ClosureMenuItem(L("位置をリセット", "Reset Position")) {
            NotificationCenter.default.post(name: .resetClockPosition, object: nil)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(L("Clockpane を終了", "Quit Clockpane")) { NSApp.terminate(nil) })
        return menu
    }

    /// タイマーの小メニュー（よく使う時間・ポモドーロ・一時停止など）
    static func timerMenu() -> NSMenu {
        let t = TimerModel.shared
        let m = NSMenu()
        if let next = t.waitingNextLabel {
            m.addItem(ClosureMenuItem(next) { t.startWaitingNext() })
            m.addItem(ClosureMenuItem(L("ポモドーロを終える", "End Pomodoro")) { t.stop() })
            m.addItem(.separator())
        }
        if t.isRunning {
            if t.isPaused {
                m.addItem(ClosureMenuItem(L("再開", "Resume")) { t.resume() })
            } else {
                m.addItem(ClosureMenuItem(L("一時停止", "Pause")) { t.pause() })
            }
            if t.isPomodoro {
                m.addItem(ClosureMenuItem(L("次へ進む", "Skip to Next")) { t.skip() })
            }
            m.addItem(ClosureMenuItem(L("止める", "Stop")) { t.stop() })
            m.addItem(.separator())
        }
        for minutes in TimerPresets.minutes {
            m.addItem(ClosureMenuItem(TimerPresets.label(minutes)) { t.startTimer(minutes: minutes) })
        }
        m.addItem(.separator())
        let work = FeatureSettings.shared.pomodoroWork
        m.addItem(ClosureMenuItem(L("ポモドーロを開始（作業\(work)分）", "Start Pomodoro (\(work)-min focus)")) { t.startPomodoro() })
        m.addItem(.separator())
        m.addItem(ClosureMenuItem(L("タイマーの設定…", "Timer Settings…")) { AppWindows.shared.showSettings(tab: .timer) })
        return m
    }

    /// アラームの小メニュー（オン・オフの切り替えと追加）
    static func alarmMenu() -> NSMenu {
        let fs = FeatureSettings.shared
        let m = NSMenu()
        for alarm in fs.alarms {
            let title = "\(alarm.timeText)  \(alarm.displayLabel)（\(alarm.repeatSummary)）"
            m.addItem(ClosureMenuItem(title, checked: alarm.enabled) { fs.setAlarm(alarm.id, enabled: !alarm.enabled) })
        }
        if !fs.alarms.isEmpty { m.addItem(.separator()) }
        m.addItem(ClosureMenuItem(L("アラームを追加・編集…", "Add or Edit Alarms…")) { AppWindows.shared.showSettings(tab: .alarms) })
        return m
    }

    static func submenu(_ title: String, _ sub: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }
}

/// よく使うタイマーの時間
enum TimerPresets {
    static let minutes = [1, 3, 5, 10, 15, 25, 30, 45, 60]
    static func label(_ m: Int) -> String {
        m == 60 ? L("1時間", "1 hour") : L("\(m)分", "\(m) min")
    }
}

/// マウスがつまみの範囲に乗っているか（ウインドウ側で調べて、つまみの表示に使う）
final class DragHandleHover: ObservableObject {
    @Published var isHovering = false
}

/// マウスを時計の中心に乗せると出る「つまみ」
/// （クリックでメニュー、ドラッグ移動がオンならドラッグで移動）
struct ClockDragHandle: View {
    /// 時計の大きさ（短い辺）に対するつまみの半径
    static let radiusRatio: CGFloat = 0.10
    @ObservedObject var settings: ClockSettings
    @ObservedObject var hover: DragHandleHover

    var body: some View {
        let c = settings.contentSize
        let d = max(28, min(c.width, c.height) * Self.radiusRatio * 2)
        let visible = hover.isHovering
        // ドラッグ移動がオンなら移動の矢印、オフならメニューの「…」
        let symbol = settings.dragEnabled ? "arrow.up.and.down.and.arrow.left.and.right" : "ellipsis"
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.45))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: d * 0.45, weight: .semibold))
                        .foregroundStyle(.white))
                .frame(width: d, height: d)
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.8)
        .animation(.easeOut(duration: 0.15), value: visible)
        .allowsHitTesting(false)
    }
}

/// デスクトップ上に時計を表示する枠なし・透明ウィンドウ
final class ClockWindowController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let settings: ClockSettings
    private let display = ClockDisplayState.shared
    private var cancellables = Set<AnyCancellable>()
    private let handleHover: DragHandleHover
    /// 影が切れないよう時計の周りに取る余白
    private let padding: CGFloat = 16
    /// いまの時計部分の高さ（つまみの位置と、大きさを変えるときの基準に使う）
    private var clockHeight: CGFloat = 0

    private let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))

    /// 時計の表示で知らせている最中か
    private var isAlertingOnClock: Bool { AlertCenter.shared.active?.style.showOnClock == true }

    init(settings: ClockSettings) {
        self.settings = settings
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let hover = DragHandleHover()
        handleHover = hover
        let root = ClockRootView(settings: settings, display: ClockDisplayState.shared, info: InfoModel.shared,
                                 alerts: AlertCenter.shared, timer: TimerModel.shared,
                                 hover: hover, padding: padding)
        let host = ClockHostingView(rootView: AnyView(root))
        host.sizingOptions = []
        panel.contentView = host

        super.init()
        panel.delegate = self
        host.canDrag = { [weak self] in self?.settings.dragEnabled ?? false }
        host.showMenu = { [weak self] event, view in self?.showClockMenu(event, in: view) }
        host.isAlerting = { [weak self] in self?.isAlertingOnClock ?? false }
        host.stopAlert = { AlertCenter.shared.stop() }

        // メニューが開いている間は、つまみの判定を止めてクリックを素通りさせる
        // （時計と重なったメニュー項目も選べるように）
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.menuIsOpen = true; self?.updateMouseThrough() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in self?.menuIsOpen = false }
            .store(in: &cancellables)

        applySettings()
        restorePosition()
        panel.orderFrontRegardless()

        // 設定・情報欄の行数・知らせの状態が変わったら、大きさや重なり順を合わせ直す
        settings.objectWillChange
            .merge(with: InfoModel.shared.objectWillChange, AlertCenter.shared.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .resetClockPosition)
            .sink { [weak self] _ in self?.resetPosition() }
            .store(in: &cancellables)

        // ディスプレイ構成が変わったら画面外に出ていないか確認
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.ensureOnScreen() }
            .store(in: &cancellables)
    }

    private func applySettings() {
        let alerting = isAlertingOnClock
        let scale: CGFloat = (alerting && AlertCenter.shared.active?.style.enlarge == true) ? 1.3 : 1
        if display.scale != scale { display.scale = scale }

        let layout = ClockLayout(settings: settings, scale: scale, rowCount: InfoModel.shared.rows.count)
        let newSize = CGSize(width: layout.width + padding * 2, height: layout.height + padding * 2)
        if panel.frame.size != newSize {
            if panel.frame.size == .zero {
                setFrameProgrammatically(NSRect(origin: .zero, size: newSize))
                clockHeight = layout.clock.height
            } else {
                // 利用者が置いた時計の中心（anchor）を基準に大きさを変える（情報欄は時計の下に伸びる）。
                // 画面の端で押し戻されても anchor は変えないので、元の大きさに戻ると元の位置に戻る。
                let center = anchor ?? clockCenter
                anchor = center
                clockHeight = layout.clock.height
                place(center: center, size: newSize)
            }
        }
        clockHeight = layout.clock.height

        // 知らせている間は、不透明にしてほかのウインドウより手前に出す
        panel.alphaValue = alerting ? 1 : settings.opacity
        if alerting {
            panel.level = .statusBar
        } else {
            // 手前に出すのは「常に手前に表示」か「ドラッグで移動」がオンのとき。
            panel.level = (settings.alwaysOnTop || settings.dragEnabled) ? .floating : desktopLevel
        }
        startHandleTracking()
        panel.orderFrontRegardless()
    }

    // MARK: 中心のつまみ

    /// ウインドウ単位でしかクリックの素通りを切り替えられないため、
    /// マウスの位置を見て、中心のつまみの上にあるときだけクリックを受け取る
    private var trackingTimer: Timer?
    /// アプリのメニューが開いている間
    private var menuIsOpen = false

    /// つまみのクリック・右クリックで、その場にメニューを出してアプリを前面にする
    private func showClockMenu(_ event: NSEvent, in view: NSView) {
        NSApp.activate(ignoringOtherApps: true)
        handleHover.isHovering = false
        let menu = ClockPopupMenu.make(settings)
        let point = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// つまみの半径：時計の大きさ（短い辺）の 10%
    private var handleRadius: CGFloat {
        let c = settings.contentSize
        return max(14, min(c.width, c.height) * ClockDragHandle.radiusRatio)
    }

    /// 画面上での時計の中心（情報欄があるときはウインドウの中心より上）
    private var clockCenter: CGPoint {
        let f = panel.frame
        return CGPoint(x: f.midX, y: f.maxY - padding - clockHeight / 2)
    }

    private func startHandleTracking() {
        guard trackingTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.updateMouseThrough() }
        RunLoop.main.add(t, forMode: .common)
        trackingTimer = t
        updateMouseThrough()
    }

    private func updateMouseThrough() {
        // 知らせている間は、時計のどこをクリックしても止められるようにする
        if isAlertingOnClock && !menuIsOpen {
            if panel.ignoresMouseEvents { panel.ignoresMouseEvents = false }
            if handleHover.isHovering { handleHover.isHovering = false }
            return
        }
        // ドラッグ中（ボタンを押している間）は切り替えない
        if !panel.ignoresMouseEvents && NSEvent.pressedMouseButtons & 1 != 0 && !menuIsOpen { return }
        let mouse = NSEvent.mouseLocation
        let c = clockCenter
        let inside = !menuIsOpen && hypot(mouse.x - c.x, mouse.y - c.y) <= handleRadius
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        // つまみはマウスが乗っている間だけ見せる（ドラッグ中は上の return で表示したまま）
        if handleHover.isHovering != inside {
            handleHover.isHovering = inside
        }
    }

    // MARK: 位置

    /// 利用者が置いた時計の中心（画面の端で一時的に押し戻されても変えない）
    private var anchor: CGPoint?
    /// こちらでウインドウを動かしている最中（windowDidMove で位置として覚えない）
    private var movingProgrammatically = false

    private func setFrameProgrammatically(_ frame: NSRect) {
        movingProgrammatically = true
        panel.setFrame(frame, display: true)
        movingProgrammatically = false
    }

    /// 時計の中心が center に来るように、size のウインドウを置く（画面からはみ出す分だけ押し戻す）
    private func place(center: CGPoint, size: CGSize) {
        let frame = NSRect(x: center.x - size.width / 2,
                           y: center.y + padding + clockHeight / 2 - size.height,
                           width: size.width, height: size.height)
        setFrameProgrammatically(clampedToScreen(frame))
    }

    private func restorePosition() {
        let d = UserDefaults.standard
        let size = panel.frame.size
        if d.object(forKey: "clockCenterX") != nil {
            // 時計の中心で覚えている（情報欄の有無でウインドウの高さが変わってもずれない）
            anchor = CGPoint(x: d.double(forKey: "clockCenterX"), y: d.double(forKey: "clockCenterY"))
        } else if d.object(forKey: "originX") != nil {
            // 以前の版はウインドウの左下で覚えていた
            let origin = NSPoint(x: d.double(forKey: "originX"), y: d.double(forKey: "originY"))
            anchor = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height - padding - clockHeight / 2)
        }
        if let anchor {
            place(center: anchor, size: size)
            ensureOnScreen()
        } else {
            placeAtDefaultPosition()
        }
    }

    private func placeAtDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        setFrameProgrammatically(NSRect(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24,
                                        width: size.width, height: size.height))
        anchor = clockCenter
    }

    private func resetPosition() {
        for key in ["originX", "originY", "clockCenterX", "clockCenterY"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        placeAtDefaultPosition()
    }

    /// ウインドウが画面の内側に収まるように位置を調整（影の余白ははみ出してよい）
    private func clampedToScreen(_ frame: NSRect) -> NSRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else { return frame }
        let area = screen.visibleFrame.insetBy(dx: -padding, dy: -padding)
        var f = frame
        if f.maxX > area.maxX { f.origin.x = area.maxX - f.width }
        if f.minX < area.minX { f.origin.x = area.minX }
        if f.maxY > area.maxY { f.origin.y = area.maxY - f.height }
        if f.minY < area.minY { f.origin.y = area.minY }
        return f
    }

    private func ensureOnScreen() {
        let frame = panel.frame
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame.insetBy(dx: frame.width * 0.3, dy: frame.height * 0.3)) }
        if !visible { resetPosition() }
    }

    func windowDidMove(_ notification: Notification) {
        // こちらで動かしたとき（大きさの変更・画面の端での押し戻し）は覚えない。
        // 利用者がドラッグして動かしたときだけ、その位置を覚える。
        guard !movingProgrammatically, clockHeight > 0 else { return }
        let c = clockCenter
        anchor = c
        UserDefaults.standard.set(c.x, forKey: "clockCenterX")
        UserDefaults.standard.set(c.y, forKey: "clockCenterY")
    }
}
