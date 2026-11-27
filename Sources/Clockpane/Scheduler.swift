import AppKit
import Combine

// MARK: - タイマー・ポモドーロ

final class TimerModel: ObservableObject {
    static let shared = TimerModel()

    enum Phase: String {
        case timer, work, shortBreak, longBreak

        var label: String {
            switch self {
            case .timer: return L("タイマー", "Timer")
            case .work: return L("作業", "Focus")
            case .shortBreak, .longBreak: return L("休憩", "Break")
            }
        }
        var icon: String {
            switch self {
            case .timer: return "⏱"
            case .work: return "🍅"
            case .shortBreak, .longBreak: return "☕"
            }
        }
        var color: RGBA {
            switch self {
            case .timer: return RGBA(0.25, 0.55, 1.0)
            case .work: return RGBA(0.95, 0.35, 0.25)
            case .shortBreak, .longBreak: return RGBA(0.30, 0.78, 0.45)
            }
        }
    }

    @Published private(set) var phase: Phase?
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    /// 「自動で次へ進む」がオフのとき、次に始める区切り（押すと始まる）
    @Published private(set) var waitingNext: (phase: Phase, minutes: Int)?
    private(set) var completedWork = 0

    /// 例：「次を開始：休憩 5分」
    var waitingNextLabel: String? {
        guard let w = waitingNext else { return nil }
        return L("次を開始：\(w.phase.label) \(w.minutes)分", "Start Next: \(w.phase.label) \(w.minutes) min")
    }

    /// 待っている次の区切り（休憩・作業）を始める
    func startWaitingNext() {
        guard let w = waitingNext else { return }
        begin(w.phase, seconds: TimeInterval(w.minutes * 60))
    }

    var isRunning: Bool { phase != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var isPomodoro: Bool { phase != nil && phase != .timer }

    func remaining(at now: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        guard let e = endDate else { return 0 }
        return max(0, e.timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        total > 0 ? remaining(at: now) / total : 0
    }

    func startTimer(minutes: Int) {
        FeatureSettings.shared.lastTimerMinutes = minutes
        begin(.timer, seconds: TimeInterval(minutes * 60))
    }

    func startPomodoro() {
        completedWork = 0
        begin(.work, seconds: TimeInterval(FeatureSettings.shared.pomodoroWork * 60))
    }

    private func begin(_ phase: Phase, seconds: TimeInterval) {
        waitingNext = nil
        self.phase = phase
        total = seconds
        endDate = Date().addingTimeInterval(seconds)
        pausedRemaining = nil
    }

    func pause() {
        guard let e = endDate, pausedRemaining == nil else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        endDate = nil
    }

    func resume() {
        guard let p = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(p)
        pausedRemaining = nil
    }

    func stop() {
        phase = nil
        endDate = nil
        pausedRemaining = nil
        total = 0
        waitingNext = nil
    }

    /// ポモドーロで、今の区切りを飛ばして次へ進む
    func skip() {
        guard let p = phase, p != .timer else { return }
        advance(from: p, notify: false)
    }

    func tick(_ now: Date) {
        guard let p = phase, let e = endDate, now >= e else { return }
        finish(p)
    }

    private func finish(_ p: Phase) {
        let fs = FeatureSettings.shared
        let style = fs.preset(fs.timerPresetID).style
        switch p {
        case .timer:
            let minutes = Int((total / 60).rounded())
            stop()
            AlertCenter.shared.fire(ActiveAlert(title: L("タイマー終了", "Timer Done"),
                                                detail: L("\(minutes)分", "\(minutes) min"),
                                                style: style, snoozeMinutes: nil))
        default:
            advance(from: p, notify: true)
        }
    }

    private func advance(from p: Phase, notify: Bool) {
        let fs = FeatureSettings.shared
        let style = fs.preset(fs.timerPresetID).style
        let next: Phase
        let minutes: Int
        if p == .work {
            completedWork += 1
            let long = completedWork % max(1, fs.pomodoroLongEvery) == 0
            next = long ? .longBreak : .shortBreak
            minutes = long ? fs.pomodoroLong : fs.pomodoroShort
            if notify {
                AlertCenter.shared.fire(ActiveAlert(title: L("作業時間が終わりました", "Focus Session Done"),
                                                    detail: L("\(minutes)分休憩しましょう", "Take a \(minutes)-min break"),
                                                    style: style, snoozeMinutes: nil))
            }
        } else {
            next = .work
            minutes = fs.pomodoroWork
            if notify {
                AlertCenter.shared.fire(ActiveAlert(title: L("休憩が終わりました", "Break Is Over"),
                                                    detail: L("次の\(minutes)分を始めましょう", "Start the next \(minutes) min"),
                                                    style: style, snoozeMinutes: nil))
            }
        }
        if fs.pomodoroAutoContinue || !notify {
            begin(next, seconds: TimeInterval(minutes * 60))
        } else {
            // 自動で進まないときは止めて、「次を開始」を押すまで待つ（回数は覚えておく）
            stop()
            waitingNext = (next, minutes)
        }
    }
}

// MARK: - 時計の下に出す情報

enum InfoRow: Hashable {
    case timer
    case event
    /// 予定の場所と会議のリンク（どちらかがあるときだけ）
    case eventDetail
    case deadline
    case world(UUID)
}

final class InfoModel: ObservableObject {
    static let shared = InfoModel()
    @Published private(set) var rows: [InfoRow] = []

    func refresh(_ now: Date) {
        let fs = FeatureSettings.shared
        var r: [InfoRow] = []
        if TimerModel.shared.isRunning { r.append(.timer) }
        if fs.calendarEnabled, let ev = CalendarService.shared.nextEvent,
           ev.start.timeIntervalSince(now) <= TimeInterval(fs.calendarShowWithinHours * 3600) {
            r.append(.event)
            if ev.location != nil || ev.link != nil { r.append(.eventDetail) }
        }
        if fs.showDeadline, fs.nearestDeadline(now) != nil { r.append(.deadline) }
        r += fs.worldCities.prefix(4).map { .world($0.id) }
        if r != rows { rows = r }
    }
}

// MARK: - 毎秒の見張り

/// アラーム・スヌーズ・タイマー・時報・予定を毎秒確かめる
final class Scheduler {
    static let shared = Scheduler()

    private var timer: Timer?
    /// アラームごとの次に鳴る日時
    private var armed: [UUID: Date] = [:]
    private var lastChimeKey = ""
    private var cancellables = Set<AnyCancellable>()

    func start() {
        rearm()
        FeatureSettings.shared.$alarms
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rearm() }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // スリープから戻ったらすぐ確かめる（過ぎてしまったアラームを知らせる）
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)

        // 時間帯（タイムゾーン）や Mac の時計が変わったら、アラームの時刻・日付の書式・予定を計算し直す
        // （例：東京で7:00に合わせたアラームが、ロンドンに移動しても現地の7:00に鳴るように）
        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .NSSystemClockDidChange))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.timeSettingsChanged() }
            .store(in: &cancellables)
    }

    private func timeSettingsChanged() {
        NSTimeZone.resetSystemTimeZone()
        ClockFormatters.reset()
        CalendarService.shared.refreshSoon()
        armed = [:]
        rearm()
        tick()
        tick()
    }

    /// アラームを作り直したとき、次に鳴る日時を計算し直す
    private func rearm() {
        let now = Date()
        var next: [UUID: Date] = [:]
        for alarm in FeatureSettings.shared.alarms where alarm.enabled {
            // すでに予定している日時が変わらないなら、そのまま（同じ秒に作り直しても取りこぼさない）
            if let current = armed[alarm.id], current > now.addingTimeInterval(-1),
               current == alarm.nextFire(after: current.addingTimeInterval(-1)) {
                next[alarm.id] = current
            } else if let date = alarm.nextFire(after: now) {
                next[alarm.id] = date
            }
        }
        armed = next
    }

    private func tick() {
        let now = Date()
        checkAlarms(now)
        AlertCenter.shared.checkSnoozes(now)
        TimerModel.shared.tick(now)
        checkChime(now)
        CalendarService.shared.tick(now)
        InfoModel.shared.refresh(now)
    }

    private func checkAlarms(_ now: Date) {
        let fs = FeatureSettings.shared
        for (id, date) in armed where date <= now {
            guard let alarm = fs.alarms.first(where: { $0.id == id && $0.enabled }) else {
                armed[id] = nil
                continue
            }
            // 2分以上過ぎていたら、スリープ中で鳴らせなかったものとして知らせる
            let missed = now.timeIntervalSince(date) > 120
            AlertCenter.shared.fire(ActiveAlert(title: alarm.displayLabel, detail: alarm.timeText,
                                                style: fs.preset(alarm.presetID).style,
                                                snoozeMinutes: alarm.snoozeMinutes, missed: missed))
            if alarm.repeatKind == .once {
                armed[id] = nil
                fs.setAlarm(id, enabled: false)
            } else {
                armed[id] = alarm.nextFire(after: now)
            }
        }
    }

    private func checkChime(_ now: Date) {
        let fs = FeatureSettings.shared
        guard fs.chimeMode != .off else { return }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        guard let hour = c.hour, let minute = c.minute, let second = c.second, second < 10 else { return }
        guard minute == 0 || (fs.chimeMode == .halfHourly && minute == 30) else { return }
        let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(hour)-\(minute)"
        guard key != lastChimeKey else { return }
        lastChimeKey = key
        if fs.chimeQuiet && Self.isQuiet(hour: hour, start: fs.chimeQuietStart, end: fs.chimeQuietEnd) { return }
        guard AlertCenter.shared.active == nil else { return }
        AlertCenter.shared.chime(sound: fs.chimeSound, volume: fs.chimeVolume, flash: fs.chimeFlash)
    }

    static func isQuiet(hour h: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (h >= start && h < end) : (h >= start || h < end)
    }
}
