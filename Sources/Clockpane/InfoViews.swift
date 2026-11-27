import SwiftUI

// MARK: - 大きさの計算（ウインドウと SwiftUI の両方で使う）

/// 知らせている間だけ時計を大きくするための倍率
final class ClockDisplayState: ObservableObject {
    static let shared = ClockDisplayState()
    @Published var scale: CGFloat = 1
}

struct ClockLayout {
    let clock: CGSize
    let info: CGSize
    let gap: CGFloat
    let infoFont: CGFloat
    let rowHeight: CGFloat

    static let rowSpacing: CGFloat = 3

    init(settings: ClockSettings, scale: CGFloat, rowCount: Int) {
        clock = ClockSettings.contentSize(style: settings.style, base: settings.size * scale,
                                          use24Hour: settings.use24Hour, showSeconds: settings.showSeconds)
        infoFont = max(11, settings.size * 0.065)
        rowHeight = infoFont * 1.75
        if rowCount > 0 {
            info = CGSize(width: infoFont * 20,
                          height: CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * Self.rowSpacing)
            gap = 6
        } else {
            info = .zero
            gap = 0
        }
    }

    var width: CGFloat { max(clock.width, info.width) }
    var height: CGFloat { clock.height + gap + info.height }
}

// MARK: - デスクトップの時計の中身

struct ClockRootView: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject var display: ClockDisplayState
    @ObservedObject var info: InfoModel
    @ObservedObject var alerts: AlertCenter
    @ObservedObject var timer: TimerModel
    let hover: DragHandleHover
    let padding: CGFloat

    var body: some View {
        let layout = ClockLayout(settings: settings, scale: display.scale, rowCount: info.rows.count)
        let base = settings.size * display.scale
        VStack(spacing: layout.gap) {
            ZStack {
                LiveClockView(settings: settings, sizeOverride: base)
                if settings.style == .analog && timer.isRunning {
                    TimerRing(timer: timer, size: base)
                }
                AlertOverlay(alerts: alerts, style: settings.style, size: layout.clock, base: base)
                ClockDragHandle(settings: settings, hover: hover)
            }
            .frame(width: layout.clock.width, height: layout.clock.height)

            if !info.rows.isEmpty {
                ClockInfoView(rows: info.rows, settings: settings, timer: timer,
                              font: layout.infoFont, rowHeight: layout.rowHeight)
                    .frame(width: layout.info.width)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - 知らせているときの表示

struct AlertOverlay: View {
    @ObservedObject var alerts: AlertCenter
    let style: ClockStyle
    let size: CGSize
    let base: CGFloat
    var body: some View {
        ZStack {
            if let alert = alerts.active, alert.style.showOnClock {
                let color = alert.style.glowColor.color
                // 点滅は時刻から明るさを決める（前の知らせの状態を引きずらず、毎回同じように点滅する）
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !alert.style.blink)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let level = alert.style.blink ? 0.25 + 0.75 * (0.5 + 0.5 * cos(t * .pi * 2)) : 1
                    ring
                        .stroke(color, lineWidth: max(3, base * 0.035))
                        .shadow(color: color, radius: base * 0.06)
                        .opacity(level)
                }

                if alert.style.showText {
                    VStack(spacing: 2) {
                        Text(alert.missed ? L("鳴らなかった：\(alert.title)", "Missed: \(alert.title)") : alert.title)
                            .font(.system(size: max(12, base * 0.075), weight: .bold))
                        if alert.location != nil || alert.linkHost != nil {
                            Text([alert.location.map { "📍 \($0)" }, alert.linkHost.map { "🔗 \($0)" }]
                                    .compactMap { $0 }.joined(separator: "  "))
                                .font(.system(size: max(10, base * 0.05), weight: .medium))
                        }
                        Text(alert.link != nil
                             ? L("クリックで止める・右クリックで参加", "Click to stop · Right-click to join")
                             : L("クリックで止める", "Click to stop"))
                            .font(.system(size: max(9, base * 0.045)))
                            .opacity(0.9)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, base * 0.06)
                    .padding(.vertical, base * 0.025)
                    .background(Capsule().fill(color.opacity(0.92)))
                    .frame(maxWidth: size.width * 0.9)
                    .frame(maxHeight: .infinity, alignment: style == .analog ? .bottom : .top)
                    .padding(style == .analog ? .bottom : .top, style == .analog ? size.height * 0.14 : -base * 0.02)
                }
            } else if alerts.chimeFlash {
                ring
                    .stroke(Color.white.opacity(0.9), lineWidth: max(2, base * 0.025))
                    .shadow(color: .white, radius: base * 0.05)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 0.4), value: alerts.chimeFlash)
        .allowsHitTesting(false)
    }

    private var ring: some Shape {
        style == .analog
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: size.height * 0.2, style: .continuous))
    }
}

// MARK: - タイマーの残りを示す輪（アナログ時計の縁）

struct TimerRing: View {
    @ObservedObject var timer: TimerModel
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = timer.progress(at: context.date)
            let color = (timer.phase?.color ?? RGBA(0.25, 0.55, 1)).color
            let width = max(3, size * 0.03)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(width / 2)
                .opacity(timer.isPaused ? 0.45 : 0.95)
                .animation(.linear(duration: 1), value: progress)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

// MARK: - 時計の下の情報欄

struct ClockInfoView: View {
    let rows: [InfoRow]
    @ObservedObject var settings: ClockSettings
    @ObservedObject var timer: TimerModel
    let font: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: ClockLayout.rowSpacing) {
                ForEach(rows, id: \.self) { row in
                    Text(text(for: row, now: context.date))
                        .font(.system(size: font, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, font * 0.7)
                        .frame(height: rowHeight)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func text(for row: InfoRow, now: Date) -> String {
        let fs = FeatureSettings.shared
        switch row {
        case .timer:
            guard let phase = timer.phase else { return "" }
            let r = Int(timer.remaining(at: now).rounded(.up))
            let time = r >= 3600
                ? String(format: "%d:%02d:%02d", r / 3600, (r % 3600) / 60, r % 60)
                : String(format: "%d:%02d", r / 60, r % 60)
            let paused = timer.isPaused ? L("（一時停止）", " (paused)") : ""
            return "\(phase.icon) \(phase.label) \(time)\(paused)"

        case .event:
            guard let ev = CalendarService.shared.nextEvent else { return "" }
            let minutes = Int((ev.start.timeIntervalSince(now) / 60).rounded(.up))
            let when = minutes < 60
                ? L("あと\(minutes)分", "in \(minutes) min")
                : L("\(clockTime(ev.start))から", "at \(clockTime(ev.start))")
            return "📅 \(ev.title)  \(when)"

        case .eventDetail:
            guard let ev = CalendarService.shared.nextEvent else { return "" }
            return [ev.location.map { "📍 \($0)" }, ev.linkHost.map { "🔗 \($0)" }]
                .compactMap { $0 }.joined(separator: "   ")

        case .deadline:
            guard let dl = fs.nearestDeadline(now) else { return "" }
            let cal = Calendar.current
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: dl.date)).day ?? 0
            let when: String
            switch days {
            case 0: when = L("今日が締切", "due today")
            case 1: when = L("明日が締切", "due tomorrow")
            default: when = L("あと\(days)日", "in \(days) days")
            }
            return "⏳ \(dl.title)  \(when)"

        case .world(let id):
            guard let city = fs.worldCities.first(where: { $0.id == id }),
                  let tz = TimeZone(identifier: city.timeZoneID) else { return "" }
            var cal = Calendar.current
            cal.timeZone = tz
            let theirDay = cal.ordinality(of: .day, in: .era, for: now) ?? 0
            let ourDay = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
            let mark: String
            switch theirDay - ourDay {
            case 1...: mark = L("（翌日）", " (+1 day)")
            case ..<0: mark = L("（前日）", " (−1 day)")
            default: mark = ""
            }
            return "🌐 \(city.name)  \(clockTime(now, in: tz))\(mark)"
        }
    }

    /// 書式は言語・時間帯・12/24時間ごとに作って使い回す（毎秒作り直さない）
    private static var formatters: [String: DateFormatter] = [:]

    private func clockTime(_ date: Date, in tz: TimeZone = .current) -> String {
        let format = settings.use24Hour ? "H:mm" : "h:mm a"
        let key = "\(settings.locale.identifier)|\(tz.identifier)|\(format)"
        let f: DateFormatter
        if let cached = Self.formatters[key] {
            f = cached
        } else {
            f = DateFormatter()
            f.locale = settings.locale
            f.timeZone = tz
            f.dateFormat = format
            Self.formatters[key] = f
        }
        return f.string(from: date)
    }
}
