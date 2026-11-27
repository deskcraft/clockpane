import EventKit
import AppKit
import Combine

/// Mac のカレンダー（同期している Google カレンダーなども含む）から次の予定を読む
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    struct UpcomingEvent: Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        /// 場所（リンクだけのときは nil）
        let location: String?
        /// 会議に参加するためのリンク（Zoom・Teams・Meet など）
        let link: URL?

        /// 例：「zoom.us」
        var linkHost: String? {
            link?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        }
    }

    /// 会議のリンクとみなすサービス
    private static let meetingHosts = ["zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com",
                                       "meet.google.com", "webex.com", "whereby.com", "gotomeeting.com",
                                       "chime.aws", "bluejeans.com", "meet.jit.si", "facetime.apple.com"]

    private static func links(in text: String?) -> [URL] {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }

    private static func isMeeting(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// 会議のリンクを探す：URL 欄・場所・メモの会議サービスのリンク → URL 欄 → 場所にあるリンクの順
    /// （メモにある資料などのリンクは、会議のリンクと取り違えないよう使わない）
    static func meetingLink(_ ev: EKEvent) -> URL? {
        let fromURL = ev.url.map { [$0] } ?? []
        let fromLocation = links(in: ev.location)
        let fromNotes = links(in: ev.notes)
        if let meeting = (fromURL + fromLocation + fromNotes).first(where: isMeeting) { return meeting }
        return fromURL.first ?? fromLocation.first
    }

    /// 場所の文字（リンクの部分は取り除き、何も残らなければ nil）
    static func placeText(_ ev: EKEvent) -> String? {
        guard var text = ev.location else { return nil }
        for url in links(in: text) { text = text.replacingOccurrences(of: url.absoluteString, with: "") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;、")))
        return trimmed.isEmpty ? nil : trimmed
    }

    @Published private(set) var nextEvent: UpcomingEvent?
    @Published private(set) var accessChanged = 0

    private let store = EKEventStore()
    private var lastFetch = Date.distantPast
    /// 24時間以内に始まる予定（始まる順）
    private var upcoming: [UpcomingEvent] = []
    /// 事前のお知らせを出した予定（同じ予定で何度も知らせない）
    private var alerted = Set<String>()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // カレンダーが変わったら読み直す（通知は別のスレッドから来ることがあるので、メインで受ける）
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.lastFetch = .distantPast }
            .store(in: &cancellables)
    }

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var isDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted || s == .writeOnly
    }

    /// 「次の予定を表示」がオンなのに、まだ許可を聞いていないとき（識別子を変えた直後など）は、起動時に聞き直す
    func requestAccessIfNeeded() {
        guard FeatureSettings.shared.calendarEnabled,
              EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        requestAccess { granted in
            if !granted { FeatureSettings.shared.calendarEnabled = false }
        }
    }

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        if isAuthorized { completion(true); return }
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.accessChanged += 1
                self.lastFetch = .distantPast
                completion(granted)
            }
        }
    }

    func tick(_ now: Date) {
        let fs = FeatureSettings.shared
        guard fs.calendarEnabled, isAuthorized else {
            if nextEvent != nil { nextEvent = nil }
            upcoming = []
            return
        }
        if now.timeIntervalSince(lastFetch) > 60 { fetch(now) }

        // 始まった予定は「次の予定」から外す（取り直しを待たずに、すぐ次の予定に切り替える）
        let next = upcoming.first { $0.start > now }
        if next != nextEvent { nextEvent = next }

        // 始まる前の知らせは、次の1件だけでなく、時間が来た予定すべてに出す（同じ時刻の予定が2つあっても両方知らせる）
        guard fs.calendarAlertMinutes > 0 else { return }
        let lead = TimeInterval(fs.calendarAlertMinutes * 60)
        for ev in upcoming where ev.start > now && ev.start.timeIntervalSince(now) <= lead {
            let key = "\(ev.id)|\(ev.start.timeIntervalSince1970)"
            guard !alerted.contains(key) else { continue }
            alerted.insert(key)
            let minutes = max(1, Int((ev.start.timeIntervalSince(now) / 60).rounded()))
            AlertCenter.shared.fire(ActiveAlert(title: ev.title,
                                                detail: L("あと\(minutes)分で始まります", "Starts in \(minutes) min"),
                                                style: fs.preset(fs.calendarPresetID).style,
                                                snoozeMinutes: nil,
                                                location: ev.location, link: ev.link))
        }
    }

    /// 次の tick で予定を読み直す（時間帯の変更など）
    func refreshSoon() { lastFetch = .distantPast }

    /// 次の予定の会議リンクを開く
    func joinNextEvent() {
        if let url = nextEvent?.link { NSWorkspace.shared.open(url) }
    }

    private func fetch(_ now: Date) {
        lastFetch = now
        let end = now.addingTimeInterval(24 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        upcoming = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map {
                UpcomingEvent(id: $0.eventIdentifier ?? UUID().uuidString,
                              title: ($0.title?.isEmpty == false ? $0.title! : L("予定", "Event")),
                              start: $0.startDate, end: $0.endDate,
                              location: Self.placeText($0), link: Self.meetingLink($0))
            }
        // 古い知らせの記録は、もう来ない予定のぶんを捨てる
        let keep = Set(upcoming.map { "\($0.id)|\($0.start.timeIntervalSince1970)" })
        alerted = alerted.filter { keep.contains($0) }
    }
}
