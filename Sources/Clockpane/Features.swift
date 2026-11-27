import SwiftUI
import AppKit
import AVFoundation
import Combine

// MARK: - 知らせ方

/// アラーム・タイマー・予定などで「どう知らせるか」
struct AlertStyle: Codable, Hashable {
    // 時計での表示
    var showOnClock = true
    var glowColor = RGBA(1.0, 0.45, 0.10)
    var blink = true
    var enlarge = false
    var showText = true
    // 音
    var playSound = true
    var soundName = "Glass"
    var volume = 0.5
    /// 鳴らす回数。0 = 止めるまで
    var soundRepeat = 3
    // そのほか
    var notify = true
    var speak = false
    /// 読み上げの声（nil = 表示言語に合わせた自動の声）
    /// ※ 以前に保存した知らせ方にはこの項目がないため、省略できる形（Optional）にしている
    var speechVoiceID: String? = nil
    /// 読み上げの速さ（0〜1。nil = 標準）
    var speechRate: Double? = nil
    /// 自動で止めるまでの秒数。0 = 止めない
    var autoStop = 60

    static let defaultSpeechRate = Double(AVSpeechUtteranceDefaultSpeechRate)
    var effectiveSpeechRate: Double { speechRate ?? Self.defaultSpeechRate }
}

/// 読み上げに使える声
enum SpeechVoices {
    /// 表示言語の声（高音質のものを先に）。選んでいる声が一覧にないときは、それも含める
    static func available(including selected: String?) -> [AVSpeechSynthesisVoice] {
        let prefix = ClockSettings.shared.isJapanese ? "ja" : "en"
        var voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { a, b in
                if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        if let id = selected, !voices.contains(where: { $0.identifier == id }),
           let v = AVSpeechSynthesisVoice(identifier: id) {
            voices.insert(v, at: 0)
        }
        return voices
    }

    static func label(_ v: AVSpeechSynthesisVoice) -> String {
        var name = v.name
        switch v.quality {
        case .premium: name += L("（プレミアム）", " (Premium)")
        case .enhanced: name += L("（拡張）", " (Enhanced)")
        default: break
        }
        if !v.language.hasPrefix(ClockSettings.shared.isJapanese ? "ja" : "en") { name += " [\(v.language)]" }
        return name
    }

    /// 速さの目安（スライダーの横に出す）
    static func rateLabel(_ rate: Double) -> String {
        let d = rate - AlertStyle.defaultSpeechRate
        if abs(d) < 0.03 { return L("標準", "Normal") }
        if d < -0.15 { return L("とてもゆっくり", "Very slow") }
        if d < 0 { return L("ゆっくり", "Slow") }
        if d > 0.15 { return L("とても速い", "Very fast") }
        return L("速い", "Fast")
    }
}

/// macOS に入っている効果音（/System/Library/Sounds）
enum SystemSound {
    static let names = ["Glass", "Ping", "Tink", "Pop", "Purr", "Hero", "Funk", "Submarine",
                        "Blow", "Bottle", "Frog", "Morse", "Sosumi", "Basso"]

    static func make(_ name: String) -> NSSound? {
        NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
    }
}

/// 名前を付けて保存した知らせ方（お気に入りにできる）
struct AlertPreset: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var style: AlertStyle

    var isBuiltin: Bool { id.hasPrefix("builtin-") }

    static let standardID = "builtin-standard"
    static let quietID = "builtin-quiet"
    static let strongID = "builtin-strong"

    /// 最初から入っている知らせ方（名前は表示言語に合わせる）
    static var builtins: [AlertPreset] {
        var quiet = AlertStyle()
        quiet.blink = false
        quiet.playSound = false
        quiet.notify = false
        quiet.autoStop = 30

        var strong = AlertStyle()
        strong.enlarge = true
        strong.soundName = "Hero"
        strong.volume = 0.8
        strong.soundRepeat = 0
        strong.speak = true
        strong.autoStop = 300

        return [
            AlertPreset(id: standardID, name: L("標準（推奨）", "Standard (Recommended)"), style: AlertStyle()),
            AlertPreset(id: quietID, name: L("静か（表示だけ）", "Quiet (visual only)"), style: quiet),
            AlertPreset(id: strongID, name: L("しっかり", "Strong"), style: strong),
        ]
    }
}

// MARK: - アラーム

enum RepeatKind: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekdays, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: return L("1回だけ", "Once")
        case .daily: return L("毎日", "Every day")
        case .weekdays: return L("平日", "Weekdays")
        case .custom: return L("曜日を選ぶ", "Choose days")
        }
    }
}

struct Alarm: Codable, Identifiable, Hashable {
    var id = UUID()
    var enabled = true
    var hour = 7
    var minute = 0
    var label = ""
    var repeatKind: RepeatKind = .once
    /// 曜日（1 = 日曜 … 7 = 土曜）。「曜日を選ぶ」のときに使う
    var weekdays: [Int] = [2, 3, 4, 5, 6]
    var presetID = AlertPreset.standardID
    var snoozeMinutes = 5

    var displayLabel: String { label.isEmpty ? L("アラーム", "Alarm") : label }
    var timeText: String { String(format: "%d:%02d", hour, minute) }

    var repeatSummary: String {
        guard repeatKind == .custom else { return repeatKind.label }
        if weekdays.isEmpty { return L("曜日なし", "No days") }
        let symbols = Self.weekdaySymbols
        return weekdays.sorted().map { symbols[($0 - 1) % 7] }.joined(separator: L("・", ", "))
    }

    static var weekdaySymbols: [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = ClockSettings.shared.locale
        return cal.shortWeekdaySymbols
    }

    private func matches(_ date: Date) -> Bool {
        let w = Calendar.current.component(.weekday, from: date)
        switch repeatKind {
        case .once, .daily: return true
        case .weekdays: return (2...6).contains(w)
        case .custom: return weekdays.contains(w)
        }
    }

    /// date より後で、次に鳴る日時
    func nextFire(after date: Date) -> Date? {
        let cal = Calendar.current
        for d in 0...7 {
            guard let day = cal.date(byAdding: .day, value: d, to: date),
                  let candidate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { continue }
            if candidate > date && matches(candidate) { return candidate }
        }
        return nil
    }
}

// MARK: - 保存データの読み込みを壊れにくくする

extension KeyedDecodingContainer {
    /// 項目がない・読めないときは fallback を使う（以前の版で保存したデータや、知らない値でも読み込めるように）
    func value<T: Decodable>(_ key: Key, _ fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

/// 配列の中の1件が読めなくても、残りは読み込む
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

func decodeLossyArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
    (try? JSONDecoder().decode([Lossy<T>].self, from: data))?.compactMap(\.value)
}

// 宣言を extension に置くことで、項目ごとに初期値を書いた memberwise init もそのまま使える
extension AlertStyle {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertStyle()
        self.init()
        showOnClock = c.value(.showOnClock, d.showOnClock)
        glowColor = c.value(.glowColor, d.glowColor)
        blink = c.value(.blink, d.blink)
        enlarge = c.value(.enlarge, d.enlarge)
        showText = c.value(.showText, d.showText)
        playSound = c.value(.playSound, d.playSound)
        soundName = c.value(.soundName, d.soundName)
        volume = c.value(.volume, d.volume)
        soundRepeat = c.value(.soundRepeat, d.soundRepeat)
        notify = c.value(.notify, d.notify)
        speak = c.value(.speak, d.speak)
        speechVoiceID = c.value(.speechVoiceID, d.speechVoiceID)
        speechRate = c.value(.speechRate, d.speechRate)
        autoStop = c.value(.autoStop, d.autoStop)
    }
}

extension Alarm {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 時刻が読めないものはアラームとして扱わない（初期値の 7:00 で勝手に鳴らないように、読み飛ばす）
        guard let h = try? c.decode(Int.self, forKey: .hour), (0...23).contains(h),
              let m = try? c.decode(Int.self, forKey: .minute), (0...59).contains(m) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "alarm without a valid time"))
        }
        let d = Alarm()
        self.init()
        id = c.value(.id, d.id)
        enabled = c.value(.enabled, d.enabled)
        hour = h
        minute = m
        label = c.value(.label, d.label)
        repeatKind = c.value(.repeatKind, d.repeatKind)
        weekdays = c.value(.weekdays, d.weekdays).filter { (1...7).contains($0) }
        presetID = c.value(.presetID, d.presetID)
        snoozeMinutes = max(1, c.value(.snoozeMinutes, d.snoozeMinutes))
    }
}

// MARK: - 時報・世界時計・締切

enum ChimeMode: String, Codable, CaseIterable, Identifiable {
    case off, hourly, halfHourly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return L("なし", "Off")
        case .hourly: return L("毎正時", "Every hour")
        case .halfHourly: return L("30分ごと", "Every 30 min")
        }
    }
}

struct WorldCity: Codable, Identifiable, Hashable {
    var id = UUID()
    var timeZoneID: String
    var name: String
}

struct Deadline: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var date: Date
}

// MARK: - 保存

/// アラーム・タイマー・時報・カレンダー・世界時計・締切の設定（UserDefaults に保存）
final class FeatureSettings: ObservableObject {
    static let shared = FeatureSettings()
    private let d = UserDefaults.standard

    // アラームと知らせ方
    @Published var alarms: [Alarm] { didSet { save(alarms, "alarms") } }
    @Published var customPresets: [AlertPreset] { didSet { save(customPresets, "alertPresets") } }
    @Published var favoritePresets: [String] { didSet { d.set(favoritePresets, forKey: "favoriteAlertPresets") } }

    // タイマー・ポモドーロ
    @Published var timerPresetID: String { didSet { d.set(timerPresetID, forKey: "timerPresetID") } }
    @Published var lastTimerMinutes: Int { didSet { d.set(lastTimerMinutes, forKey: "lastTimerMinutes") } }
    @Published var pomodoroWork: Int { didSet { d.set(pomodoroWork, forKey: "pomodoroWork") } }
    @Published var pomodoroShort: Int { didSet { d.set(pomodoroShort, forKey: "pomodoroShort") } }
    @Published var pomodoroLong: Int { didSet { d.set(pomodoroLong, forKey: "pomodoroLong") } }
    @Published var pomodoroLongEvery: Int { didSet { d.set(pomodoroLongEvery, forKey: "pomodoroLongEvery") } }
    @Published var pomodoroAutoContinue: Bool { didSet { d.set(pomodoroAutoContinue, forKey: "pomodoroAutoContinue") } }

    // 時報
    @Published var chimeMode: ChimeMode { didSet { d.set(chimeMode.rawValue, forKey: "chimeMode") } }
    @Published var chimeSound: String { didSet { d.set(chimeSound, forKey: "chimeSound") } }
    @Published var chimeVolume: Double { didSet { d.set(chimeVolume, forKey: "chimeVolume") } }
    @Published var chimeFlash: Bool { didSet { d.set(chimeFlash, forKey: "chimeFlash") } }
    @Published var chimeQuiet: Bool { didSet { d.set(chimeQuiet, forKey: "chimeQuiet") } }
    @Published var chimeQuietStart: Int { didSet { d.set(chimeQuietStart, forKey: "chimeQuietStart") } }
    @Published var chimeQuietEnd: Int { didSet { d.set(chimeQuietEnd, forKey: "chimeQuietEnd") } }

    // カレンダー
    @Published var calendarEnabled: Bool { didSet { d.set(calendarEnabled, forKey: "calendarEnabled") } }
    @Published var calendarShowWithinHours: Int { didSet { d.set(calendarShowWithinHours, forKey: "calendarShowWithinHours") } }
    @Published var calendarAlertMinutes: Int { didSet { d.set(calendarAlertMinutes, forKey: "calendarAlertMinutes") } }
    @Published var calendarPresetID: String { didSet { d.set(calendarPresetID, forKey: "calendarPresetID") } }

    // 世界時計・締切
    @Published var worldCities: [WorldCity] { didSet { save(worldCities, "worldCities") } }
    @Published var deadlines: [Deadline] { didSet { save(deadlines, "deadlines") } }
    @Published var showDeadline: Bool { didSet { d.set(showDeadline, forKey: "showDeadline") } }

    private init() {
        PreferencesMigration.runOnce()
        /// 配列を1件ずつ読む（1件が壊れていても、残りは消さない）
        func load<T: Decodable>(_ key: String, _ fallback: [T]) -> [T] {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let value = decodeLossyArray(T.self, from: data) else { return fallback }
            return value
        }
        let d = UserDefaults.standard
        alarms = load("alarms", [])
        customPresets = load("alertPresets", [])
        favoritePresets = d.stringArray(forKey: "favoriteAlertPresets") ?? [AlertPreset.standardID]

        timerPresetID = d.string(forKey: "timerPresetID") ?? AlertPreset.standardID
        lastTimerMinutes = d.object(forKey: "lastTimerMinutes") as? Int ?? 10
        pomodoroWork = d.object(forKey: "pomodoroWork") as? Int ?? 25
        pomodoroShort = d.object(forKey: "pomodoroShort") as? Int ?? 5
        pomodoroLong = d.object(forKey: "pomodoroLong") as? Int ?? 15
        pomodoroLongEvery = d.object(forKey: "pomodoroLongEvery") as? Int ?? 4
        pomodoroAutoContinue = d.object(forKey: "pomodoroAutoContinue") as? Bool ?? true

        chimeMode = ChimeMode(rawValue: d.string(forKey: "chimeMode") ?? "") ?? .off
        chimeSound = d.string(forKey: "chimeSound") ?? "Tink"
        chimeVolume = d.object(forKey: "chimeVolume") as? Double ?? 0.4
        chimeFlash = d.object(forKey: "chimeFlash") as? Bool ?? true
        chimeQuiet = d.object(forKey: "chimeQuiet") as? Bool ?? true
        chimeQuietStart = d.object(forKey: "chimeQuietStart") as? Int ?? 22
        chimeQuietEnd = d.object(forKey: "chimeQuietEnd") as? Int ?? 7

        calendarEnabled = d.object(forKey: "calendarEnabled") as? Bool ?? false
        calendarShowWithinHours = d.object(forKey: "calendarShowWithinHours") as? Int ?? 3
        calendarAlertMinutes = d.object(forKey: "calendarAlertMinutes") as? Int ?? 5
        calendarPresetID = d.string(forKey: "calendarPresetID") ?? AlertPreset.standardID

        worldCities = load("worldCities", [])
        deadlines = load("deadlines", [])
        showDeadline = d.object(forKey: "showDeadline") as? Bool ?? true
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: key) }
    }

    // MARK: 知らせ方の一覧

    var allPresets: [AlertPreset] { AlertPreset.builtins + customPresets }

    /// お気に入りを先頭（追加した順）に並べた一覧
    var orderedPresets: [AlertPreset] {
        let all = allPresets
        let favs = favoritePresets.compactMap { id in all.first { $0.id == id } }
        return favs + all.filter { !favoritePresets.contains($0.id) }
    }

    func preset(_ id: String) -> AlertPreset {
        allPresets.first { $0.id == id } ?? AlertPreset.builtins[0]
    }

    func presetLabel(_ id: String) -> String {
        let p = preset(id)
        return isFavorite(p.id) ? "★ \(p.name)" : p.name
    }

    func isFavorite(_ id: String) -> Bool { favoritePresets.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favoritePresets.firstIndex(of: id) { favoritePresets.remove(at: i) } else { favoritePresets.append(id) }
    }

    func savePreset(_ preset: AlertPreset) {
        if let i = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[i] = preset
        } else {
            customPresets.append(preset)
        }
    }

    /// 削除した知らせ方を使っていたものは「標準」に戻す
    func deletePreset(_ id: String) {
        customPresets.removeAll { $0.id == id }
        favoritePresets.removeAll { $0 == id }
        for i in alarms.indices where alarms[i].presetID == id { alarms[i].presetID = AlertPreset.standardID }
        if timerPresetID == id { timerPresetID = AlertPreset.standardID }
        if calendarPresetID == id { calendarPresetID = AlertPreset.standardID }
    }

    // MARK: アラーム

    func saveAlarm(_ alarm: Alarm) {
        if let i = alarms.firstIndex(where: { $0.id == alarm.id }) { alarms[i] = alarm } else { alarms.append(alarm) }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func setAlarm(_ id: UUID, enabled: Bool) {
        if let i = alarms.firstIndex(where: { $0.id == id }) { alarms[i].enabled = enabled }
    }

    func deleteAlarm(_ id: UUID) { alarms.removeAll { $0.id == id } }

    /// 今日以降で一番近い締切
    func nearestDeadline(_ now: Date) -> Deadline? {
        let today = Calendar.current.startOfDay(for: now)
        return deadlines.filter { Calendar.current.startOfDay(for: $0.date) >= today }.min { $0.date < $1.date }
    }
}
