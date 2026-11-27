import SwiftUI
import Combine

enum ClockStyle: String, CaseIterable, Identifiable {
    case analog, digital
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .analog: return L("アナログ", "Analog")
        case .digital: return L("デジタル", "Digital")
        }
    }
}

// MARK: - 表示言語

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return L("システムに合わせる", "Match System")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

// MARK: - 識別子の変更にともなう設定の引き継ぎ

/// 公開にあたって識別子を local.clockpane.Clockpane → io.github.deskcraft.clockpane に変えたので、
/// 以前の設定をすべて一度だけ引き継ぐ。どの設定よりも先に読む必要があるため、
/// ClockSettings・FeatureSettings の最初で呼ぶ。
enum PreferencesMigration {
    static let oldDomain = "local.clockpane.Clockpane"
    private static var done = false

    static func runOnce() {
        guard !done else { return }
        done = true
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleIdentifier != oldDomain,
              !defaults.bool(forKey: "migratedFromLocalClockpane") else { return }
        defaults.set(true, forKey: "migratedFromLocalClockpane")

        let domain = oldDomain as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              let values = CFPreferencesCopyMultiple(keys as CFArray, domain, kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost) as? [String: Any] else { return }
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        // 以前「ログイン時に起動」をオンにしていたら、新しい識別子で登録し直す（起動後に行う）
        if (values["loginItemRegistration"] as? String) == "enabled" {
            defaults.set(true, forKey: "reRegisterLoginItem")
        }
    }
}

/// 画面に出す文字を、選んでいる言語に合わせて日本語か英語で返す
func L(_ ja: String, _ en: String) -> String {
    ClockSettings.shared.isJapanese ? ja : en
}

/// すべての設定を UserDefaults に保存する共有モデル
final class ClockSettings: ObservableObject {
    static let shared = ClockSettings()
    private let defaults = UserDefaults.standard

    @Published var style: ClockStyle { didSet { defaults.set(style.rawValue, forKey: "style") } }
    /// 選んでいるデザインの ID（標準は "retro" など、カスタムは "custom-…"）
    @Published var designID: String { didSet { defaults.set(designID, forKey: "design") } }
    /// 自分で作ったデザイン
    @Published var customDesigns: [CustomDesign] {
        didSet {
            if let data = try? JSONEncoder().encode(customDesigns) { defaults.set(data, forKey: "customDesigns") }
        }
    }
    @Published var use24Hour: Bool { didSet { defaults.set(use24Hour, forKey: "use24Hour") } }
    @Published var showSeconds: Bool { didSet { defaults.set(showSeconds, forKey: "showSeconds") } }
    @Published var showDate: Bool { didSet { defaults.set(showDate, forKey: "showDate") } }
    /// アナログ時計の直径（pt）。デジタルはこれを基準に大きさを決める
    @Published var size: Double { didSet { defaults.set(size, forKey: "size") } }
    /// 0.2〜1.0
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    /// オン: 時計を手前に出してドラッグで移動できる / オフ: デスクトップに固定（クリックは素通り）
    @Published var dragEnabled: Bool { didSet { defaults.set(dragEnabled, forKey: "dragEnabled") } }
    /// オン: ほかのウインドウより常に手前に表示（クリックは素通り）
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    /// オン: Dock にアイコンを表示（Dock に固定できる）/ オフ: メニューバーだけ（設定・ヘルプを開いている間は Dock に出る）
    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }
    /// お気に入りのデザイン ID（追加した順）
    @Published var favoriteDesigns: [String] {
        didSet { defaults.set(favoriteDesigns, forKey: "favoriteDesigns") }
    }
    /// 表示言語（システムに合わせる / 日本語 / English）
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "language") } }

    var isJapanese: Bool {
        switch language {
        case .ja: return true
        case .en: return false
        case .system: return (Locale.preferredLanguages.first ?? "").hasPrefix("ja")
        }
    }

    /// 日付・曜日の表記に使うロケール
    var locale: Locale { Locale(identifier: isJapanese ? "ja_JP" : "en_US") }

    // MARK: デザイン一覧

    /// 標準のデザイン → 自分で作ったデザインの順
    var allDesigns: [DesignItem] {
        ClockDesign.allCases.map(\.item) + customDesigns.map(\.item)
    }

    /// お気に入りを先頭（追加した順）に、残りは標準の順で並べた一覧
    var orderedDesigns: [DesignItem] {
        let all = allDesigns
        let favs = favoriteDesigns.compactMap { id in all.first { $0.id == id } }
        return favs + all.filter { !favoriteDesigns.contains($0.id) }
    }

    var currentDesign: DesignItem {
        allDesigns.first { $0.id == designID } ?? ClockDesign.defaultDesign.item
    }

    func isFavorite(_ id: String) -> Bool { favoriteDesigns.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favoriteDesigns.firstIndex(of: id) {
            favoriteDesigns.remove(at: i)
        } else {
            favoriteDesigns.append(id)
        }
    }

    // MARK: カスタムデザインの保存・削除

    /// 新しく追加、または同じ ID のものを置き換えて、そのデザインを選ぶ
    func saveCustom(_ design: CustomDesign) {
        if let i = customDesigns.firstIndex(where: { $0.id == design.id }) {
            customDesigns[i] = design
        } else {
            customDesigns.append(design)
        }
        designID = design.item.id
    }

    func deleteCustom(_ id: UUID) {
        guard let design = customDesigns.first(where: { $0.id == id }) else { return }
        let itemID = design.item.id
        customDesigns.removeAll { $0.id == id }
        favoriteDesigns.removeAll { $0 == itemID }
        if designID == itemID { designID = ClockDesign.defaultDesign.rawValue }
    }

    func customDesign(_ id: UUID) -> CustomDesign? { customDesigns.first { $0.id == id } }

    /// 同じ名前が無いように「名前 2」「名前 3」…を付ける
    func uniqueName(_ base: String) -> String {
        let names = Set(allDesigns.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// 旧名「デスクトップ時計」(local.desktopclock.DesktopClock) の設定を一度だけ引き継ぐ
    private static func migrateFromOldName(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "migratedFromDesktopClock") else { return }
        defaults.set(true, forKey: "migratedFromDesktopClock")
        guard let old = UserDefaults(suiteName: "local.desktopclock.DesktopClock") else { return }
        let keys = ["style", "design", "use24Hour", "showSeconds", "showDate", "size", "opacity",
                    "dragEnabled", "alwaysOnTop", "showInDock", "originX", "originY"]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    private init() {
        PreferencesMigration.runOnce()
        Self.migrateFromOldName(UserDefaults.standard)
        style = ClockStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .analog
        designID = defaults.string(forKey: "design") ?? ClockDesign.defaultDesign.rawValue
        // 1件ずつ読む（1件が壊れていても、ほかの自作デザインは消さない）
        if let data = defaults.data(forKey: "customDesigns"),
           let saved = decodeLossyArray(CustomDesign.self, from: data) {
            customDesigns = saved
        } else {
            customDesigns = []
        }
        use24Hour = defaults.object(forKey: "use24Hour") as? Bool ?? true
        showSeconds = defaults.object(forKey: "showSeconds") as? Bool ?? true
        showDate = defaults.object(forKey: "showDate") as? Bool ?? true
        size = defaults.object(forKey: "size") as? Double ?? 200
        opacity = defaults.object(forKey: "opacity") as? Double ?? 0.9
        dragEnabled = defaults.object(forKey: "dragEnabled") as? Bool ?? false
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? false
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        favoriteDesigns = defaults.stringArray(forKey: "favoriteDesigns") ?? []
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        replaceCustomCopiesOfBuiltins()
        renameOldDesignIDs()
    }

    /// 名前を変えた標準デザインの古い ID を新しい ID に置き換える（選択中・お気に入り）
    private func renameOldDesignIDs() {
        let renamed = ["wallCustom": ClockDesign.grace.rawValue]
        if let new = renamed[designID] { designID = new }
        if favoriteDesigns.contains(where: { renamed[$0] != nil }) {
            favoriteDesigns = favoriteDesigns.map { renamed[$0] ?? $0 }
        }
    }

    /// 標準に組み込まれたのと同じ中身のカスタムデザインは、標準のほうに置き換えて重複を消す
    /// （選択中・お気に入りも標準のほうへ移す）。
    /// 「Grace」を標準に組み込んだときの一度だけの移し替え。毎回行うと、利用者が標準を
    /// そのまま複製したデザインまで起動のたびに消えてしまうため、2回目以降は何もしない。
    private func replaceCustomCopiesOfBuiltins() {
        guard !defaults.bool(forKey: "replacedBuiltinCopiesOnce") else { return }
        defaults.set(true, forKey: "replacedBuiltinCopiesOnce")
        for custom in customDesigns {
            guard let builtin = ClockDesign.allCases.first(where: { $0.palette == custom.palette }) else { continue }
            let oldID = custom.itemID
            if designID == oldID { designID = builtin.rawValue }
            favoriteDesigns = favoriteDesigns.map { $0 == oldID ? builtin.rawValue : $0 }
            var seen = Set<String>()
            favoriteDesigns = favoriteDesigns.filter { seen.insert($0).inserted }
            customDesigns.removeAll { $0.id == custom.id }
        }
    }

    var contentSize: CGSize {
        Self.contentSize(style: style, base: size, use24Hour: use24Hour, showSeconds: showSeconds)
    }

    static func contentSize(style: ClockStyle, base: CGFloat, use24Hour: Bool, showSeconds: Bool) -> CGSize {
        switch style {
        case .analog:
            return CGSize(width: base, height: base)
        case .digital:
            let width = base * (showSeconds ? 1.75 : 1.35) + (use24Hour ? 0 : base * 0.3)
            return CGSize(width: width, height: base * 0.55)
        }
    }
}

extension Notification.Name {
    static let resetClockPosition = Notification.Name("ClockpaneResetPosition")
}
