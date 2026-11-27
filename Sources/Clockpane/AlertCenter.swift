import AppKit
import AVFoundation
import UserNotifications

/// いま知らせている内容
struct ActiveAlert: Equatable {
    let id = UUID()
    /// 例：「会議」「タイマー終了」
    var title: String
    /// 例：「10:00」「あと5分で始まります」
    var detail: String
    var style: AlertStyle
    /// スヌーズできる分数（nil ならスヌーズなし）
    var snoozeMinutes: Int?
    /// Mac がスリープしていて時刻を過ぎてしまった
    var missed = false
    /// 予定の場所
    var location: String? = nil
    /// 会議に参加するためのリンク
    var link: URL? = nil
    /// 設定画面の「試す」で出したもの（本物の知らせを邪魔しない）
    var isPreview = false

    var linkHost: String? {
        link?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }
}

/// 音・読み上げ・通知センター・時計での表示をまとめて扱う
final class AlertCenter: NSObject, ObservableObject, NSSoundDelegate,
                         AVSpeechSynthesizerDelegate, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()

    @Published private(set) var active: ActiveAlert?
    /// 時報のときに一瞬だけ時計を光らせる
    @Published private(set) var chimeFlash = false

    private var sound: NSSound?
    private var previewSound: NSSound?
    private var playingStyle: AlertStyle?
    /// 残りの再生回数（-1 = 止めるまで）
    private var remainingPlays = 0
    private var autoStopTimer: Timer?
    private let speech = AVSpeechSynthesizer()
    /// いま読み上げている文（読み上げ後に音を鳴らすとき、別の知らせと取り違えないため）
    private var currentUtterance: AVSpeechUtterance?
    private var snoozed: [(date: Date, alert: ActiveAlert)] = []
    /// 知らせている間に来た、次の知らせ（順番に知らせる）
    private var pending: [ActiveAlert] = []
    /// 最近の知らせ（通知センターのボタンが押されたとき、どの知らせかを探すため）
    private var recent: [UUID: ActiveAlert] = [:]
    private var recentOrder: [UUID] = []
    /// すでに通知センターに出した知らせ
    private var notified = Set<UUID>()

    /// スヌーズのボタン付き
    private static let category = "CLOCKPANE_ALERT"
    /// 止めるボタンだけ（タイマー・予定など、スヌーズしない知らせ）
    private static let plainCategory = "CLOCKPANE_PLAIN"
    /// 会議のリンクがある予定用（「参加する」ボタン付き）
    private static let meetingCategory = "CLOCKPANE_MEETING"
    private static let stopAction = "STOP"
    private static let snoozeAction = "SNOOZE"
    private static let joinAction = "JOIN"

    override init() {
        super.init()
        speech.delegate = self
    }

    // MARK: 通知センター

    func setUpNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let stop = UNNotificationAction(identifier: Self.stopAction, title: L("止める", "Stop"))
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: L("スヌーズ", "Snooze"))
        let join = UNNotificationAction(identifier: Self.joinAction, title: L("参加する", "Join"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [stop, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.plainCategory, actions: [stop], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.meetingCategory, actions: [join, stop], intentIdentifiers: []),
        ])
        refreshNotificationStatus()
    }

    /// まだ聞いていなければ、通知の許可を macOS に求める
    func requestNotificationPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in self.refreshNotificationStatus() }
        }
    }

    // MARK: 通知の許可の状態（設定画面に表示する）

    enum NotificationPermission: String {
        case unknown, notAsked, allowed, denied, noBanners
        var label: String {
            switch self {
            case .unknown: return L("確認中…", "Checking…")
            case .notAsked: return L("まだ許可を求めていません", "Not requested yet")
            case .allowed: return L("許可されています", "Allowed")
            case .denied: return L("許可されていません", "Not allowed")
            case .noBanners: return L("許可されていますが、バナーが「なし」になっています", "Allowed, but banners are set to None")
            }
        }
    }

    @Published private(set) var notificationPermission: NotificationPermission = .unknown

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let p: NotificationPermission
            switch s.authorizationStatus {
            case .notDetermined: p = .notAsked
            case .denied: p = .denied
            default: p = s.alertStyle == .none ? .noBanners : .allowed
            }
            DispatchQueue.main.async {
                self.notificationPermission = p
                // 状態を設定にも書き出しておく（不具合を調べるとき用）
                UserDefaults.standard.set(p.rawValue, forKey: "notificationPermission")
            }
        }
    }

    /// システム設定の「通知」→ Clockpane を開く
    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                    "x-apple.systempreferences:com.apple.preference.notifications"]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            self.refreshNotificationStatus()
        }
    }

    private func postNotification(_ alert: ActiveAlert) {
        guard !notified.contains(alert.id) else { return }
        notified.insert(alert.id)
        let content = UNMutableNotificationContent()
        content.title = alert.missed ? L("鳴らなかったアラーム：\(alert.title)", "Missed: \(alert.title)") : alert.title
        var body = alert.missed
            ? L("\(alert.detail) の予定でしたが、Mac がスリープしていました。", "Scheduled for \(alert.detail) while the Mac was asleep.")
            : alert.detail
        if let place = alert.location { body += "\n📍 \(place)" }
        if let host = alert.linkHost { body += "\n🔗 \(host)" }
        content.body = body
        content.categoryIdentifier = alert.link != nil ? Self.meetingCategory
            : (alert.snoozeMinutes != nil ? Self.category : Self.plainCategory)
        if let link = alert.link { content.userInfo = ["link": link.absoluteString] }
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { center.add(request) }
                    self.refreshNotificationStatus()
                }
            } else {
                center.add(request)
                self.refreshNotificationStatus()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let id = UUID(uuidString: response.notification.request.identifier)
        let link = (response.notification.request.content.userInfo["link"] as? String).flatMap(URL.init(string:))
        DispatchQueue.main.async {
            // 押された通知の知らせにだけ効かせる（いま鳴っている別の知らせは止めない）
            switch action {
            case Self.snoozeAction:
                self.snooze(id: id)
            case Self.joinAction:
                if let link { NSWorkspace.shared.open(link) }
                self.stop(id: id)
            default:
                self.stop(id: id)
            }
            completionHandler()
        }
    }

    // MARK: 知らせる・止める

    func fire(_ alert: ActiveAlert) {
        remember(alert)
        if let current = active, !current.isPreview {
            // 本物の知らせが出ている間は、「試す」は出さない
            if alert.isPreview { return }
            // 鳴っている知らせは止めずに順番待ちにする（通知センターには先に出す）
            pending.append(alert)
            if alert.style.notify || alert.missed { postNotification(alert) }
            return
        }
        start(alert)
    }

    private func start(_ alert: ActiveAlert) {
        stopOutputs()
        active = alert
        let style = alert.style
        playingStyle = style

        if style.notify || alert.missed { postNotification(alert) }

        if !alert.missed {
            if style.speak {
                speak(alert)
            } else if style.playSound {
                startSoundLoop(style)
            }
        }

        let seconds = alert.missed ? 30 : style.autoStop
        if seconds > 0 {
            autoStopTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                self?.stop(byUser: false)
            }
        }
    }

    private func remember(_ alert: ActiveAlert) {
        if recent[alert.id] == nil { recentOrder.append(alert.id) }
        recent[alert.id] = alert
        while recentOrder.count > 50 {
            let old = recentOrder.removeFirst()
            recent[old] = nil
            notified.remove(old)
        }
    }

    /// byUser: 自分で止めたとき true（通知センターからも消す）。
    /// 自動で止まったときは、あとで見返せるよう通知センターに残す。
    /// 順番待ちの知らせがあれば、続けて知らせる。
    func stop(byUser: Bool = true) {
        stopOutputs()
        if byUser, let id = active?.id.uuidString {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }
        active = nil
        if !pending.isEmpty {
            let next = pending.removeFirst()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let current = self.active, !current.isPreview { self.pending.insert(next, at: 0) } else { self.start(next) }
            }
        }
    }

    /// 通知センターで押された知らせを止める（いま出ていなければ、順番待ちと通知だけ片付ける）
    private func stop(id: UUID?) {
        guard let id else { return }
        if active?.id == id {
            stop()
        } else {
            pending.removeAll { $0.id == id }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        }
    }

    /// いま知らせている予定の会議リンクを開いて止める
    func joinActive() {
        if let link = active?.link { NSWorkspace.shared.open(link) }
        stop()
    }

    /// いまの知らせを止めて、決めた分数のあとにもう一度知らせる
    func snooze() {
        snooze(id: active?.id)
    }

    /// 指定した知らせをスヌーズする（自動で止まったあとの通知から押されても効く）
    private func snooze(id: UUID?) {
        guard let id, let alert = active?.id == id ? active : recent[id] else { return }
        guard let minutes = alert.snoozeMinutes else { stop(id: id); return }
        stop(id: id)
        var again = alert
        again.missed = false
        snoozed.append((Date().addingTimeInterval(TimeInterval(minutes * 60)), again))
    }

    /// スヌーズしていたものの時刻が来たら知らせる（毎秒呼ばれる）
    func checkSnoozes(_ now: Date) {
        guard let i = snoozed.firstIndex(where: { $0.date <= now }) else { return }
        let item = snoozed.remove(at: i)
        // もう一度通知センターにも出せるように
        notified.remove(item.alert.id)
        fire(item.alert)
    }

    /// 設定画面の「試す」：最長10秒だけ知らせる（本物の知らせが出ている間は何もしない）
    func preview(_ style: AlertStyle, title: String? = nil) {
        var s = style
        s.autoStop = s.autoStop == 0 ? 10 : min(s.autoStop, 10)
        fire(ActiveAlert(title: title ?? L("テスト", "Test"),
                         detail: ClockFormatters.time24.string(from: Date()),
                         style: s, snoozeMinutes: nil, isPreview: true))
    }

    /// 音の種類を選ぶときの試聴（1回だけ）
    func previewSound(_ name: String, volume: Double) {
        previewSound?.stop()
        previewSound = SystemSound.make(name)
        previewSound?.volume = Float(volume)
        previewSound?.play()
    }

    /// 時報：1回だけ鳴らし、必要なら時計を一瞬光らせる
    func chime(sound name: String, volume: Double, flash: Bool) {
        previewSound(name, volume: volume)
        guard flash else { return }
        chimeFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.chimeFlash = false }
    }

    // MARK: 音と読み上げ

    private func stopOutputs() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        remainingPlays = 0
        playingStyle = nil
        currentUtterance = nil
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        sound?.stop()
        sound = nil
    }

    private func startSoundLoop(_ style: AlertStyle) {
        remainingPlays = style.soundRepeat == 0 ? -1 : style.soundRepeat
        playNext()
    }

    private func playNext() {
        guard let style = playingStyle, remainingPlays != 0 else { return }
        if remainingPlays > 0 { remainingPlays -= 1 }
        guard let snd = SystemSound.make(style.soundName) else { return }
        snd.volume = Float(style.volume)
        snd.delegate = self
        sound = snd
        snd.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        guard flag, sound === self.sound else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, sound === self.sound else { return }
            self.playNext()
        }
    }

    private func speak(_ alert: ActiveAlert) {
        let text = L("\(alert.detail)です。\(alert.title)", "It's \(alert.detail). \(alert.title)")
        let u = Self.utterance(text, style: alert.style)
        currentUtterance = u
        speech.speak(u)
    }

    /// 知らせ方の声・速さ・音量で読み上げる文を作る
    private static func utterance(_ text: String, style: AlertStyle) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        if let id = style.speechVoiceID, let voice = AVSpeechSynthesisVoice(identifier: id) {
            u.voice = voice
        } else {
            u.voice = AVSpeechSynthesisVoice(language: ClockSettings.shared.isJapanese ? "ja-JP" : "en-US")
        }
        u.rate = Float(min(max(style.effectiveSpeechRate, Double(AVSpeechUtteranceMinimumSpeechRate)),
                           Double(AVSpeechUtteranceMaximumSpeechRate)))
        u.volume = Float(style.volume)
        return u
    }

    private let previewSpeech = AVSpeechSynthesizer()

    /// 声と速さを選ぶときの試聴（例文を1回読み上げる）
    func previewVoice(_ style: AlertStyle) {
        if previewSpeech.isSpeaking { previewSpeech.stopSpeaking(at: .immediate) }
        let text = L("10時です。会議の時間です。", "It's 10 o'clock. Time for the meeting.")
        previewSpeech.speak(Self.utterance(text, style: style))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 読み上げのあとに音を鳴らす（その間に別の知らせに替わっていたら鳴らさない）
            guard utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            if let style = self.playingStyle, style.playSound { self.startSoundLoop(style) }
        }
    }
}
