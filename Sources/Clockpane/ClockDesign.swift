import SwiftUI
import AppKit

// MARK: - 保存できる色

/// 保存（JSON）できる色。sRGB の赤・緑・青・不透明度（0〜1）
struct RGBA: Codable, Hashable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    init(white w: Double, _ a: Double = 1) { self.init(w, w, w, a) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(Double(ns.redComponent), Double(ns.greenComponent),
                  Double(ns.blueComponent), Double(ns.alphaComponent))
    }

    static let white = RGBA(1, 1, 1)
    static let black = RGBA(0, 0, 0)
    static let clear = RGBA(0, 0, 0, 0)

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    func opacity(_ x: Double) -> RGBA { RGBA(r, g, b, a * x) }
}

// MARK: - 部品の種類

enum NumeralStyle: String, Codable, CaseIterable, Identifiable {
    case none, arabic, roman, quarters
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L("なし", "None")
        case .arabic: return L("1〜12", "1–12")
        case .roman: return L("ローマ数字", "Roman numerals")
        case .quarters: return L("12・3・6・9", "12·3·6·9")
        }
    }
}

enum NumeralFont: String, Codable, CaseIterable, Identifiable {
    case standard, rounded, serif, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return L("ゴシック", "Sans-serif")
        case .rounded: return L("丸ゴシック", "Rounded")
        case .serif: return L("明朝・セリフ", "Serif")
        case .mono: return L("等幅", "Monospaced")
        }
    }
    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

enum MinuteMarkStyle: String, Codable, CaseIterable, Identifiable {
    case line, dot, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: return L("線", "Lines")
        case .dot: return L("点", "Dots")
        case .none: return L("なし", "None")
        }
    }
}

enum HandShape: String, Codable, CaseIterable, Identifiable {
    case bar, round, tapered, spade
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bar: return L("角", "Square")
        case .round: return L("丸", "Round")
        case .tapered: return L("先細", "Tapered")
        case .spade: return L("飾り", "Ornate")
        }
    }
}

enum SecondStyle: String, Codable, CaseIterable, Identifiable {
    case hand, handDot, dots
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hand: return L("細い針", "Thin hand")
        case .handDot: return L("先に丸", "With dot")
        case .dots: return L("点が点灯", "Lit dots")
        }
    }
}

enum DateContent: String, Codable, CaseIterable, Identifiable {
    case dayWeekday, monthDayWeekday, day, weekday
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dayWeekday: return L("日と曜日", "Day and weekday")
        case .monthDayWeekday: return L("月日と曜日", "Month, day and weekday")
        case .day: return L("日だけ", "Day only")
        case .weekday: return L("曜日だけ", "Weekday only")
        }
    }
}

enum DatePosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .bottom: return L("下", "Bottom")
        case .top: return L("上", "Top")
        case .right: return L("右（窓）", "Right (window)")
        }
    }
}

// MARK: - デザインの中身

struct ClockPalette: Codable, Hashable {
    // 盤面（背景）と縁
    var faceTop: RGBA
    var faceBottom: RGBA
    var rimLight: RGBA
    var rimDark: RGBA
    /// 盤面に対する縁の太さ（直径比）
    var rimWidth: Double
    /// 縁の内側に点の飾りを付ける
    var beads: Bool = false
    // 目盛りと針
    var tick: RGBA
    var hand: RGBA
    var second: RGBA
    // 数字
    var numerals: NumeralStyle = .none
    var numeralFont: NumeralFont = .standard
    /// nil のときは目盛りと同じ色
    var numeralColor: RGBA? = nil
    var numeralScale: Double = 1.0
    /// 数字を置く位置（盤面の半径比）
    var numeralRadius: Double = 0.60
    // 目盛り
    var minuteMarks: MinuteMarkStyle = .line
    /// 時の目盛りの内側・外側の位置（盤面の半径比）と太さ（直径比）。太さ 0 で時の目盛りなし
    var hourTickInner: Double = 0.76
    var hourTickOuter: Double = 0.94
    var hourTickWidth: Double = 0.024
    // 針
    /// 時針・分針の太さの倍率
    var handWeight: Double = 1.0
    var handShape: HandShape = .bar
    var secondStyle: SecondStyle = .hand
    // 日付
    var dateContent: DateContent = .dayWeekday
    var datePosition: DatePosition = .bottom
    /// nil のときは目盛りと同じ色
    var dateColor: RGBA? = nil
    /// 影を付けて壁紙の上でも読めるようにする
    var dropShadow: Bool = true

    var numeralTint: RGBA { numeralColor ?? tick }
    var dateTint: RGBA { dateColor ?? tick.opacity(0.85) }
}

/// 保存したデザインの読み込み：項目がない・読めないときは Retro の値を使う
/// （extension に置くことで、項目ごとの初期値つきの memberwise init もそのまま使える）
extension ClockPalette {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClockDesign.retro.palette
        self = d
        faceTop = c.value(.faceTop, d.faceTop)
        faceBottom = c.value(.faceBottom, d.faceBottom)
        rimLight = c.value(.rimLight, d.rimLight)
        rimDark = c.value(.rimDark, d.rimDark)
        rimWidth = c.value(.rimWidth, d.rimWidth)
        beads = c.value(.beads, d.beads)
        tick = c.value(.tick, d.tick)
        hand = c.value(.hand, d.hand)
        second = c.value(.second, d.second)
        numerals = c.value(.numerals, d.numerals)
        numeralFont = c.value(.numeralFont, d.numeralFont)
        numeralColor = c.value(.numeralColor, d.numeralColor)
        numeralScale = c.value(.numeralScale, d.numeralScale)
        numeralRadius = c.value(.numeralRadius, d.numeralRadius)
        minuteMarks = c.value(.minuteMarks, d.minuteMarks)
        hourTickInner = c.value(.hourTickInner, d.hourTickInner)
        hourTickOuter = c.value(.hourTickOuter, d.hourTickOuter)
        hourTickWidth = c.value(.hourTickWidth, d.hourTickWidth)
        handWeight = c.value(.handWeight, d.handWeight)
        handShape = c.value(.handShape, d.handShape)
        secondStyle = c.value(.secondStyle, d.secondStyle)
        dateContent = c.value(.dateContent, d.dateContent)
        datePosition = c.value(.datePosition, d.datePosition)
        dateColor = c.value(.dateColor, d.dateColor)
        dropShadow = c.value(.dropShadow, d.dropShadow)
    }
}

// MARK: - 標準のデザイン

enum ClockDesign: String, CaseIterable, Identifiable {
    /// grace がアプリの標準（初めて起動したときに使うデザイン）
    static let defaultDesign: ClockDesign = .grace

    case grace, retro, broadcast, wall, kitchen, cottage, flat,
         office, roman, midnight, navy, neon, paper, mint, sakura, minimal, glass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grace: return "Grace"
        case .retro: return "Retro"
        case .broadcast: return "Broadcast"
        case .wall: return "Wall"
        case .kitchen: return "Kitchen"
        case .cottage: return "Cottage"
        case .flat: return "Flat"
        case .office: return "Office"
        case .roman: return "Roman"
        case .midnight: return "Midnight"
        case .navy: return "Navy"
        case .neon: return "Neon"
        case .paper: return "Paper"
        case .mint: return "Mint"
        case .sakura: return "Sakura"
        case .minimal: return "Minimal"
        case .glass: return "Glass"
        }
    }

    /// 設定画面で名前の下に出す短い説明
    var caption: String {
        switch self {
        case .grace: return L("縁なし・飾り針", "Rimless, ornate hands")
        case .retro: return L("駅の時計風", "Railway station style")
        case .broadcast: return L("放送局の時計風", "Broadcast studio style")
        case .wall: return L("細い線の壁掛け", "Thin-line wall clock")
        case .kitchen: return L("大きな数字", "Large numbers")
        case .cottage: return L("飾り縁と飾り針", "Ornate rim and hands")
        case .flat: return L("黒い縁のフラット", "Flat with black rim")
        case .office: return L("クラシック", "Classic")
        case .roman: return L("ローマ数字", "Roman numerals")
        case .midnight: return L("ダーク", "Dark")
        case .navy: return L("紺と金", "Navy and gold")
        case .neon: return L("ネオン", "Neon")
        case .paper: return L("モノクロ", "Monochrome")
        case .mint: return L("パステル", "Pastel")
        case .sakura: return L("桜色", "Cherry blossom")
        case .minimal: return L("透明・線だけ", "Transparent, lines only")
        case .glass: return L("半透明", "Translucent")
        }
    }

    var item: DesignItem {
        DesignItem(id: rawValue, name: displayName, caption: caption, palette: palette, customID: nil)
    }

    var palette: ClockPalette {
        switch self {
        case .grace:
            // Grace：利用者が Wall をもとに作ったデザインを標準に組み込んだもの（縁なし、細い線の目盛り、飾り針、赤い秒針、日付は右の小窓）
            return ClockPalette(
                faceTop: .white, faceBottom: RGBA(white: 0.96),
                rimLight: RGBA(white: 0.96), rimDark: RGBA(white: 0.78), rimWidth: 0,
                tick: RGBA(white: 0.15), hand: RGBA(white: 0.10), second: RGBA(1, 0.1491314173, 0),
                minuteMarks: .none,
                hourTickInner: 0.82, hourTickOuter: 0.92, hourTickWidth: 0.007,
                handWeight: 0.925130890052356, handShape: .spade,
                datePosition: .right)
        case .retro:
            return ClockPalette(
                faceTop: RGBA(white: 0.98), faceBottom: RGBA(white: 0.90),
                rimLight: RGBA(white: 0.92), rimDark: RGBA(white: 0.62), rimWidth: 0.035,
                tick: RGBA(white: 0.28), hand: RGBA(white: 0.25), second: RGBA(0.85, 0.25, 0.22),
                secondStyle: .handDot)
        case .broadcast:
            return ClockPalette(
                faceTop: .white, faceBottom: RGBA(white: 0.97),
                rimLight: RGBA(white: 0.85), rimDark: RGBA(white: 0.70), rimWidth: 0.008,
                tick: RGBA(white: 0.08), hand: RGBA(white: 0.08), second: RGBA(white: 0.08),
                minuteMarks: .none,
                hourTickInner: 0.62, hourTickOuter: 0.82, hourTickWidth: 0.045,
                handWeight: 1.35, secondStyle: .dots)
        case .wall:
            // 白い樹脂の縁、細い線の目盛り、細長い針
            return ClockPalette(
                faceTop: .white, faceBottom: RGBA(white: 0.96),
                rimLight: RGBA(white: 0.96), rimDark: RGBA(white: 0.78), rimWidth: 0.035,
                tick: RGBA(white: 0.15), hand: RGBA(white: 0.10), second: RGBA(white: 0.10),
                minuteMarks: .none,
                hourTickInner: 0.82, hourTickOuter: 0.92, hourTickWidth: 0.007,
                handWeight: 0.6, handShape: .round,
                dateContent: .day, datePosition: .right)
        case .kitchen:
            // 太い白の縁、大きな丸い数字、先細の針
            return ClockPalette(
                faceTop: .white, faceBottom: RGBA(white: 0.97),
                rimLight: .white, rimDark: RGBA(white: 0.80), rimWidth: 0.06,
                tick: RGBA(white: 0.10), hand: RGBA(white: 0.08), second: RGBA(white: 0.10),
                numerals: .arabic, numeralFont: .rounded, numeralScale: 1.45, numeralRadius: 0.74,
                minuteMarks: .none, hourTickWidth: 0,
                handWeight: 1.1, handShape: .tapered)
        case .cottage:
            // 厚い白の縁に点の飾り、セリフの数字、飾りの針
            return ClockPalette(
                faceTop: RGBA(white: 0.96), faceBottom: RGBA(white: 0.91),
                rimLight: .white, rimDark: RGBA(white: 0.84), rimWidth: 0.085, beads: true,
                tick: RGBA(white: 0.12), hand: RGBA(white: 0.08), second: RGBA(white: 0.12),
                numerals: .arabic, numeralFont: .serif, numeralScale: 1.3, numeralRadius: 0.72,
                minuteMarks: .none, hourTickWidth: 0,
                handWeight: 1.0, handShape: .spade)
        case .flat:
            // 黒い太めの縁、白い盤面、短い線の目盛り、赤い秒針
            return ClockPalette(
                faceTop: .white, faceBottom: .white,
                rimLight: RGBA(white: 0.28), rimDark: RGBA(white: 0.12), rimWidth: 0.06,
                tick: RGBA(white: 0.10), hand: RGBA(white: 0.05), second: RGBA(0.85, 0.15, 0.15),
                minuteMarks: .none,
                hourTickInner: 0.84, hourTickOuter: 0.92, hourTickWidth: 0.009,
                handWeight: 0.9, dropShadow: true)
        case .office:
            return ClockPalette(
                faceTop: RGBA(0.99, 0.97, 0.90), faceBottom: RGBA(0.94, 0.90, 0.80),
                rimLight: RGBA(0.86, 0.76, 0.52), rimDark: RGBA(0.55, 0.43, 0.22), rimWidth: 0.05,
                tick: RGBA(0.25, 0.18, 0.10), hand: RGBA(0.20, 0.14, 0.08), second: RGBA(0.65, 0.12, 0.12),
                numerals: .arabic, numeralFont: .serif, handShape: .round)
        case .roman:
            return ClockPalette(
                faceTop: RGBA(1.0, 0.98, 0.93), faceBottom: RGBA(0.95, 0.92, 0.85),
                rimLight: RGBA(white: 0.30), rimDark: RGBA(white: 0.08), rimWidth: 0.04,
                tick: RGBA(white: 0.10), hand: RGBA(white: 0.10), second: RGBA(0.60, 0.10, 0.10),
                numerals: .roman, numeralFont: .serif, numeralRadius: 0.68,
                hourTickInner: 0.86, hourTickWidth: 0.012)
        case .midnight:
            return ClockPalette(
                faceTop: RGBA(white: 0.14), faceBottom: RGBA(white: 0.04),
                rimLight: RGBA(white: 0.45), rimDark: RGBA(white: 0.12), rimWidth: 0.035,
                tick: RGBA(white: 0.95), hand: RGBA(white: 0.95), second: RGBA(1.0, 0.55, 0.10),
                numerals: .arabic, numeralFont: .rounded, handShape: .round)
        case .navy:
            return ClockPalette(
                faceTop: RGBA(0.10, 0.16, 0.32), faceBottom: RGBA(0.05, 0.08, 0.18),
                rimLight: RGBA(0.92, 0.80, 0.52), rimDark: RGBA(0.55, 0.42, 0.20), rimWidth: 0.04,
                tick: RGBA(0.93, 0.82, 0.56), hand: RGBA(0.93, 0.82, 0.56), second: .white,
                numerals: .quarters, numeralFont: .serif, handShape: .round)
        case .neon:
            return ClockPalette(
                faceTop: RGBA(0.04, 0.02, 0.08), faceBottom: .black,
                rimLight: RGBA(0.30, 0.90, 1.0), rimDark: RGBA(0.65, 0.20, 0.95), rimWidth: 0.018,
                tick: RGBA(0.35, 0.95, 1.0), hand: .white, second: RGBA(1.0, 0.30, 0.80),
                minuteMarks: .dot, handShape: .round)
        case .paper:
            return ClockPalette(
                faceTop: .white, faceBottom: .white,
                rimLight: .black, rimDark: .black, rimWidth: 0.014,
                tick: .black, hand: .black, second: .black,
                numerals: .arabic, hourTickInner: 0.84, hourTickWidth: 0.014)
        case .mint:
            return ClockPalette(
                faceTop: RGBA(0.80, 0.93, 0.86), faceBottom: RGBA(0.68, 0.87, 0.78),
                rimLight: .white, rimDark: RGBA(white: 0.85), rimWidth: 0.03,
                tick: RGBA(0.15, 0.40, 0.30), hand: RGBA(0.15, 0.40, 0.30), second: RGBA(1.0, 0.50, 0.40),
                numerals: .quarters, numeralFont: .rounded, minuteMarks: .dot, handShape: .round)
        case .sakura:
            return ClockPalette(
                faceTop: RGBA(1.0, 0.93, 0.95), faceBottom: RGBA(0.98, 0.84, 0.88),
                rimLight: .white, rimDark: RGBA(0.90, 0.75, 0.80), rimWidth: 0.03,
                tick: RGBA(0.60, 0.20, 0.35), hand: RGBA(0.45, 0.15, 0.28), second: RGBA(0.90, 0.30, 0.50),
                numerals: .arabic, numeralFont: .rounded, minuteMarks: .dot, handShape: .round)
        case .minimal:
            return ClockPalette(
                faceTop: .clear, faceBottom: .clear,
                rimLight: .clear, rimDark: .clear, rimWidth: 0,
                tick: .white, hand: .white, second: RGBA(1.0, 0.45, 0.40),
                handShape: .round)
        case .glass:
            return ClockPalette(
                faceTop: RGBA(white: 1, 0.30), faceBottom: RGBA(white: 1, 0.10),
                rimLight: RGBA(white: 1, 0.75), rimDark: RGBA(white: 1, 0.25), rimWidth: 0.02,
                tick: .white, hand: .white, second: RGBA(0.35, 0.85, 1.0),
                numerals: .arabic, numeralFont: .rounded, handShape: .round)
        }
    }
}

// MARK: - 自分で作ったデザイン

struct CustomDesign: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var palette: ClockPalette

    /// 一覧で使う ID（設定の読み込み中にも使えるよう、表示用の文字は含めない）
    var itemID: String { "custom-\(id.uuidString)" }

    var item: DesignItem {
        DesignItem(id: itemID, name: name, caption: L("カスタム", "Custom"), palette: palette, customID: id)
    }
}

/// 一覧・メニューに並べる1つのデザイン（標準またはカスタム）
struct DesignItem: Identifiable, Hashable {
    let id: String
    let name: String
    let caption: String
    let palette: ClockPalette
    let customID: UUID?
    var isCustom: Bool { customID != nil }
}
