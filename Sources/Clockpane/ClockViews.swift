import SwiftUI

// MARK: - 日付フォーマット

/// 日付・時刻の書式。選んでいる言語（日本語／英語）ごとに作って使い回す
enum ClockFormatters {
    private static var cache: [String: DateFormatter] = [:]

    /// 時間帯が変わったときに作り直す
    static func reset() { cache.removeAll() }

    private static func formatter(_ pattern: String, template: Bool) -> DateFormatter {
        let locale = ClockSettings.shared.locale
        let tz = TimeZone.current
        let key = "\(locale.identifier)|\(tz.identifier)|\(template)|\(pattern)"
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = tz
        if template { f.setLocalizedDateFormatFromTemplate(pattern) } else { f.dateFormat = pattern }
        cache[key] = f
        return f
    }
    private static func make(_ format: String) -> DateFormatter { formatter(format, template: false) }
    private static func template(_ t: String) -> DateFormatter { formatter(t, template: true) }

    static var time24: DateFormatter { make("HH:mm") }
    static var time24s: DateFormatter { make("HH:mm:ss") }
    static var time12: DateFormatter { make("h:mm") }
    static var time12s: DateFormatter { make("h:mm:ss") }
    static var ampm: DateFormatter { make("a") }
    static var monthDayWeekday: DateFormatter { template("MMMdEEE") }
    static var dayWeekday: DateFormatter { template("dEEE") }
    static var day: DateFormatter { template("d") }
    static var weekday: DateFormatter { template("EEE") }
    static var weekdayLong: DateFormatter { template("EEEE") }

    /// アナログ時計の盤面に出す日付
    static func analogDate(_ date: Date, _ content: DateContent) -> String {
        switch content {
        case .dayWeekday: return dayWeekday.string(from: date)
        case .monthDayWeekday: return monthDayWeekday.string(from: date)
        case .day: return day.string(from: date)
        case .weekday: return weekday.string(from: date)
        }
    }

    /// デジタル時計の下に出す日付
    static func digitalDate(_ date: Date, _ content: DateContent) -> String {
        switch content {
        case .dayWeekday, .monthDayWeekday: return monthDayWeekday.string(from: date)
        case .day: return day.string(from: date)
        case .weekday: return weekdayLong.string(from: date)
        }
    }
}

// MARK: - 共通ビュー（デスクトップ用ウィンドウと設定画面のプレビューで共用）

struct ClockFaceView: View {
    let date: Date
    let style: ClockStyle
    let palette: ClockPalette
    let use24Hour: Bool
    let showSeconds: Bool
    let showDate: Bool
    let size: CGFloat

    var body: some View {
        let content = ClockSettings.contentSize(style: style, base: size, use24Hour: use24Hour, showSeconds: showSeconds)
        Group {
            switch style {
            case .analog:
                AnalogClockView(date: date, palette: palette, showSeconds: showSeconds, showDate: showDate)
            case .digital:
                DigitalClockView(date: date, palette: palette, use24Hour: use24Hour,
                                 showSeconds: showSeconds, showDate: showDate, height: content.height)
            }
        }
        .frame(width: content.width, height: content.height)
        .shadow(color: .black.opacity(palette.dropShadow ? 0.35 : 0), radius: size * 0.03, y: size * 0.015)
    }
}

/// 1秒ごと（秒の頭にそろえて）更新する時計
struct LiveClockView: View {
    @ObservedObject var settings: ClockSettings
    var sizeOverride: CGFloat? = nil
    var paletteOverride: ClockPalette? = nil
    var styleOverride: ClockStyle? = nil

    private static var alignedStart: Date {
        Date(timeIntervalSinceReferenceDate: floor(Date().timeIntervalSinceReferenceDate))
    }

    var body: some View {
        TimelineView(.periodic(from: Self.alignedStart, by: 1)) { context in
            ClockFaceView(date: context.date,
                          style: styleOverride ?? settings.style,
                          palette: paletteOverride ?? settings.currentDesign.palette,
                          use24Hour: settings.use24Hour,
                          showSeconds: settings.showSeconds,
                          showDate: settings.showDate,
                          size: sizeOverride ?? settings.size)
        }
    }
}

// MARK: - アナログ

struct AnalogClockView: View {
    let date: Date
    let palette: ClockPalette
    let showSeconds: Bool
    let showDate: Bool

    private static func point(_ c: CGPoint, _ degrees: Double, _ r: CGFloat) -> CGPoint {
        let rad = degrees * .pi / 180
        return CGPoint(x: c.x + CGFloat(sin(rad)) * r, y: c.y - CGFloat(cos(rad)) * r)
    }

    private static func dot(_ ctx: GraphicsContext, _ p: CGPoint, _ d: CGFloat, _ color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(color))
    }

    /// 中心から角度 angle の方向に、(長さ方向, 幅方向) の点を並べた多角形
    private static func polygon(_ c: CGPoint, _ angle: Double, _ pts: [(CGFloat, CGFloat)]) -> Path {
        let rad = angle * .pi / 180
        let d = CGPoint(x: sin(rad), y: -cos(rad))   // 針の向き
        let n = CGPoint(x: cos(rad), y: sin(rad))    // 針に直角な向き
        var path = Path()
        for (i, (along, across)) in pts.enumerated() {
            let p = CGPoint(x: c.x + d.x * along + n.x * across, y: c.y + d.y * along + n.y * across)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    private static func drawHand(_ ctx: GraphicsContext, center c: CGPoint, angle: Double,
                                 length L: CGFloat, tail T: CGFloat, width w: CGFloat,
                                 color: Color, shape: HandShape) {
        switch shape {
        case .bar, .round:
            var path = Path()
            path.move(to: point(c, angle + 180, T))
            path.addLine(to: point(c, angle, L))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: w, lineCap: shape == .round ? .round : .butt))
        case .tapered:
            ctx.fill(polygon(c, angle, [(-T, -w * 0.5), (L, -w * 0.08), (L, w * 0.08), (-T, w * 0.5)]),
                     with: .color(color))
        case .spade:
            // 細い軸の先にひし形の飾り
            ctx.fill(polygon(c, angle, [
                (-T, -w * 0.25), (L * 0.66, -w * 0.25), (L * 0.80, -w * 0.80), (L, 0),
                (L * 0.80, w * 0.80), (L * 0.66, w * 0.25), (-T, w * 0.25),
            ]), with: .color(color))
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let p = palette
            let side = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let faceRect = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
            let tick = p.tick.color

            // 縁
            if p.rimWidth > 0 {
                ctx.fill(Path(ellipseIn: faceRect),
                         with: .linearGradient(Gradient(colors: [p.rimLight.color, p.rimDark.color]),
                                               startPoint: CGPoint(x: faceRect.minX, y: faceRect.minY),
                                               endPoint: CGPoint(x: faceRect.maxX, y: faceRect.maxY)))
            }
            // 盤面（背景）
            let inner = faceRect.insetBy(dx: side * p.rimWidth, dy: side * p.rimWidth)
            ctx.fill(Path(ellipseIn: inner),
                     with: .linearGradient(Gradient(colors: [p.faceTop.color, p.faceBottom.color]),
                                           startPoint: CGPoint(x: inner.midX, y: inner.minY),
                                           endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
            let ir = inner.width / 2

            // 縁の内側の点の飾り
            if p.beads {
                for i in 0..<96 {
                    Self.dot(ctx, Self.point(c, Double(i) * 3.75, ir * 0.965), side * 0.011, p.rimDark.color)
                }
            }

            let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let sec = comps.second ?? 0
            let s = Double(sec)
            let m = Double(comps.minute ?? 0) + s / 60
            let h = Double((comps.hour ?? 0) % 12) + m / 60

            // 目盛り
            for i in 0..<60 {
                let angle = Double(i) * 6
                if i % 5 == 0 {
                    guard p.hourTickWidth > 0 else { continue }
                    var path = Path()
                    path.move(to: Self.point(c, angle, ir * p.hourTickInner))
                    path.addLine(to: Self.point(c, angle, ir * p.hourTickOuter))
                    ctx.stroke(path, with: .color(tick),
                               style: StrokeStyle(lineWidth: side * p.hourTickWidth, lineCap: .butt))
                } else {
                    switch p.minuteMarks {
                    case .line:
                        var path = Path()
                        path.move(to: Self.point(c, angle, ir * 0.87))
                        path.addLine(to: Self.point(c, angle, ir * 0.94))
                        ctx.stroke(path, with: .color(tick), style: StrokeStyle(lineWidth: side * 0.008))
                    case .dot:
                        Self.dot(ctx, Self.point(c, angle, ir * 0.91), side * 0.012, tick.opacity(0.8))
                    case .none:
                        break
                    }
                }
            }

            // 秒を点で表す（放送局の時計風）：0秒から今の秒までの点が点灯
            if showSeconds && p.secondStyle == .dots {
                for i in 0..<60 {
                    Self.dot(ctx, Self.point(c, Double(i) * 6, ir * 0.92),
                             side * (i % 5 == 0 ? 0.026 : 0.02),
                             i <= sec ? p.second.color : tick.opacity(0.12))
                }
            }

            // 数字
            let romans = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
            if p.numerals != .none {
                for hour in 1...12 {
                    let label: String
                    var fontScale: CGFloat = 0.17
                    switch p.numerals {
                    case .arabic: label = "\(hour)"
                    case .roman: label = romans[hour % 12]; fontScale = 0.14
                    case .quarters:
                        guard hour % 3 == 0 else { continue }
                        label = "\(hour)"; fontScale = 0.22
                    case .none: continue
                    }
                    let text = ctx.resolve(Text(label)
                        .font(.system(size: ir * fontScale * p.numeralScale, weight: .semibold,
                                      design: p.numeralFont.design))
                        .foregroundColor(p.numeralTint.color))
                    ctx.draw(text, at: Self.point(c, Double(hour) * 30, ir * p.numeralRadius))
                }
            }

            // 日付・曜日
            if showDate {
                let text = ctx.resolve(Text(ClockFormatters.analogDate(date, p.dateContent))
                    .font(.system(size: ir * 0.12, weight: .medium, design: p.numeralFont.design))
                    .foregroundColor(p.dateTint.color))
                let offset = ir * (p.numerals == .none ? 0.36 : 0.30)
                switch p.datePosition {
                case .bottom:
                    ctx.draw(text, at: CGPoint(x: c.x, y: c.y + offset))
                case .top:
                    ctx.draw(text, at: CGPoint(x: c.x, y: c.y - offset))
                case .right:
                    // 3時の方向に小さな窓を作って表示
                    let at = CGPoint(x: c.x + ir * (p.numerals == .none ? 0.52 : 0.38), y: c.y)
                    let ts = text.measure(in: CGSize(width: side, height: side))
                    let box = CGRect(x: at.x - ts.width / 2 - ir * 0.04, y: at.y - ts.height / 2 - ir * 0.02,
                                     width: ts.width + ir * 0.08, height: ts.height + ir * 0.04)
                    let shape = Path(roundedRect: box, cornerRadius: ir * 0.02)
                    ctx.fill(shape, with: .color(p.faceTop.color))
                    ctx.stroke(shape, with: .color(tick.opacity(0.35)), lineWidth: max(0.5, side * 0.003))
                    ctx.draw(text, at: at)
                }
            }

            // 針
            var handCtx = ctx
            if p.dropShadow {
                handCtx.addFilter(.shadow(color: .black.opacity(0.3), radius: side * 0.012, x: 0, y: side * 0.008))
            }
            let shapeScale: CGFloat = p.handShape == .tapered ? 1.6 : (p.handShape == .spade ? 1.1 : 1.0)
            Self.drawHand(handCtx, center: c, angle: h * 30, length: ir * 0.55, tail: ir * 0.12,
                          width: side * 0.04 * p.handWeight * shapeScale, color: p.hand.color, shape: p.handShape)
            Self.drawHand(handCtx, center: c, angle: m * 6, length: ir * 0.86, tail: ir * 0.12,
                          width: side * 0.028 * p.handWeight * shapeScale, color: p.hand.color, shape: p.handShape)

            let showSecondHand = showSeconds && p.secondStyle != .dots
            if showSecondHand {
                let withDot = p.secondStyle == .handDot
                Self.drawHand(handCtx, center: c, angle: s * 6, length: ir * (withDot ? 0.62 : 0.90),
                              tail: ir * 0.22, width: side * 0.009, color: p.second.color, shape: .bar)
                if withDot {
                    Self.dot(handCtx, Self.point(c, s * 6, ir * 0.62), side * 0.05, p.second.color)
                }
            }
            Self.dot(ctx, c, side * 0.035 * (p.secondStyle == .dots ? 1.3 : 1),
                     showSecondHand ? p.second.color : p.hand.color)
        }
    }
}

// MARK: - デジタル

struct DigitalClockView: View {
    let date: Date
    let palette: ClockPalette
    let use24Hour: Bool
    let showSeconds: Bool
    let showDate: Bool
    let height: CGFloat

    private var timeString: String {
        let f: DateFormatter
        switch (use24Hour, showSeconds) {
        case (true, true): f = ClockFormatters.time24s
        case (true, false): f = ClockFormatters.time24
        case (false, true): f = ClockFormatters.time12s
        case (false, false): f = ClockFormatters.time12
        }
        return f.string(from: date)
    }

    var body: some View {
        let p = palette
        let fontDesign: Font.Design = p.numeralFont == .standard ? .rounded : p.numeralFont.design
        let shape = RoundedRectangle(cornerRadius: height * 0.2, style: .continuous)
        VStack(spacing: height * 0.02) {
            HStack(alignment: .firstTextBaseline, spacing: height * 0.06) {
                if !use24Hour {
                    Text(ClockFormatters.ampm.string(from: date))
                        .font(.system(size: height * (showDate ? 0.15 : 0.18), weight: .medium))
                }
                Text(timeString)
                    .font(.system(size: height * (showDate ? 0.42 : 0.52), weight: .light, design: fontDesign))
                    .monospacedDigit()
            }
            .foregroundStyle(p.numeralTint.color)
            if showDate {
                Text(ClockFormatters.digitalDate(date, p.dateContent))
                    .font(.system(size: height * 0.14, weight: .medium))
                    .foregroundStyle(p.dateTint.color)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.3)
        .padding(.horizontal, height * 0.15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(LinearGradient(colors: [p.faceTop.color, p.faceBottom.color],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(
            LinearGradient(colors: [p.rimLight.color, p.rimDark.color], startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: p.rimWidth > 0 ? max(1.5, height * p.rimWidth * 0.8) : 0))
    }
}
