import SwiftUI
import AppKit

// MARK: - 設定画面のタブ

enum SettingsTab: String, CaseIterable, Identifiable {
    case clock, design, alarms, timer, more, general
    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return L("時計", "Clock")
        case .design: return L("デザイン", "Design")
        case .alarms: return L("アラーム", "Alarms")
        case .timer: return L("タイマー・時報", "Timer & Chime")
        case .more: return L("予定・世界時計", "Calendar & World")
        case .general: return L("一般", "General")
        }
    }

    var icon: String {
        switch self {
        case .clock: return "clock"
        case .design: return "paintpalette"
        case .alarms: return "alarm"
        case .timer: return "timer"
        case .more: return "calendar"
        case .general: return "gearshape"
        }
    }
}

/// 見出しの横に ⓘ を付け、押したときだけ説明を出す（長い説明で画面が伸びないように）
struct InfoHeader: View {
    let title: String
    let info: String
    @State private var showing = false

    init(_ title: String, info: String) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button {
                showing.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help(L("説明を表示", "Show explanation"))
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                Text(info)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 320, alignment: .leading)
                    .padding(14)
            }
        }
    }
}

final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .clock
}

// MARK: - 共通の部品

/// 知らせ方を選ぶ（お気に入りは ★ 付きで先頭）
struct PresetPicker: View {
    let title: String
    @Binding var selection: String
    @ObservedObject private var fs = FeatureSettings.shared

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(fs.orderedPresets) { p in
                Text(fs.isFavorite(p.id) ? "★ \(p.name)" : p.name).tag(p.id)
            }
        }
    }
}

/// 効果音を選ぶ（▶︎ で試聴）
struct SoundPicker: View {
    let title: String
    @Binding var name: String
    let volume: Double

    var body: some View {
        HStack {
            Picker(title, selection: $name) {
                ForEach(SystemSound.names, id: \.self) { Text($0).tag($0) }
            }
            Button {
                AlertCenter.shared.previewSound(name, volume: volume)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help(L("試聴する", "Preview"))
        }
    }
}

struct PercentSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: 0.05...1.0)
                Text("\(Int((value * 100).rounded())) %").monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            .frame(width: 260)
        }
    }
}

/// 知らせ方の中身。編集画面を2列にするため、左（表示と音）と右（読み上げ・通知・停止）に分けて出す
struct AlertStyleEditor: View {
    enum Part { case lookAndSound, speechAndOther }

    @Binding var style: AlertStyle
    let part: Part

    var body: some View {
        switch part {
        case .lookAndSound: lookAndSound
        case .speechAndOther: speechAndOther
        }
    }

    @ViewBuilder
    private var lookAndSound: some View {
        Section(L("時計での表示", "On the Clock")) {
            Toggle(L("時計を手前に出して光らせる", "Bring the clock to the front and glow"), isOn: $style.showOnClock)
            if style.showOnClock {
                ColorPicker(L("光の色", "Glow color"),
                            selection: Binding(get: { style.glowColor.color }, set: { style.glowColor = RGBA($0) }),
                            supportsOpacity: false)
                Toggle(L("点滅する", "Blink"), isOn: $style.blink)
                Toggle(L("大きく表示する", "Enlarge the clock"), isOn: $style.enlarge)
                Toggle(L("名前を表示する", "Show the name"), isOn: $style.showText)
            }
        }
        Section {
            Toggle(L("音を鳴らす", "Play a sound"), isOn: $style.playSound)
            if style.playSound {
                SoundPicker(title: L("音の種類", "Sound"), name: $style.soundName, volume: style.volume)
                PercentSlider(title: L("音量", "Volume"), value: $style.volume)
                Picker(L("鳴らす回数", "Repeat"), selection: $style.soundRepeat) {
                    Text(L("1回", "Once")).tag(1)
                    Text(L("3回", "3 times")).tag(3)
                    Text(L("5回", "5 times")).tag(5)
                    Text(L("10回", "10 times")).tag(10)
                    Text(L("止めるまで", "Until stopped")).tag(0)
                }
            }
        } header: {
            InfoHeader(L("音", "Sound"),
                       info: L("音量の上限は Mac 本体の音量です。消音にしていると鳴りません。",
                               "The Mac’s own volume is the upper limit. No sound plays while the Mac is muted."))
        }
    }

    @ViewBuilder
    private var speechAndOther: some View {
        Section {
            Toggle(L("名前を読み上げる", "Speak the name"), isOn: $style.speak)
            if style.speak {
                Picker(L("声", "Voice"), selection: $style.speechVoiceID) {
                    Text(L("自動（おすすめ）", "Automatic (Recommended)")).tag(String?.none)
                    ForEach(SpeechVoices.available(including: style.speechVoiceID), id: \.identifier) { v in
                        Text(SpeechVoices.label(v)).tag(String?.some(v.identifier))
                    }
                }
                LabeledContent(L("速さ", "Speed")) {
                    HStack {
                        Text(L("ゆっくり", "Slow")).font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { style.effectiveSpeechRate },
                                              set: { style.speechRate = $0 }),
                               in: 0.3...0.7)
                        Text(L("速い", "Fast")).font(.caption).foregroundStyle(.secondary)
                        Text(SpeechVoices.rateLabel(style.effectiveSpeechRate))
                            .monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                    .frame(width: 290)
                }
                HStack {
                    Button {
                        AlertCenter.shared.previewVoice(style)
                    } label: {
                        Label(L("声を試聴する", "Preview Voice"), systemImage: "play.circle")
                    }
                    Spacer()
                    if style.speechRate != nil {
                        Button(L("速さを標準に戻す", "Reset Speed")) { style.speechRate = nil }
                    }
                }
            }
        } header: {
            InfoHeader(L("読み上げ", "Speech"),
                       info: L("知らせるときに、時刻と名前を読み上げます（例：「10:00です。会議」）。読み上げのあとに音が鳴ります。高音質の声は、システム設定 →「アクセシビリティ」→「読み上げコンテンツ」→「システムの声」から追加できます。",
                               "Speaks the time and name when alerting (e.g. “It's 10:00. Meeting”), then plays the sound. Add higher-quality voices in System Settings → Accessibility → Spoken Content → System Voice."))
        }

        Section(L("通知と停止", "Notification and Stop")) {
            Toggle(L("通知センターに出す", "Show in Notification Center"), isOn: $style.notify)
            Picker(L("自動で止める", "Stop automatically"), selection: $style.autoStop) {
                Text(L("30秒後", "After 30 sec")).tag(30)
                Text(L("1分後", "After 1 min")).tag(60)
                Text(L("3分後", "After 3 min")).tag(180)
                Text(L("5分後", "After 5 min")).tag(300)
                Text(L("止めない", "Never")).tag(0)
            }
        }
    }
}

// MARK: - アラームのタブ

struct AlarmSettingsView: View {
    @ObservedObject private var fs = FeatureSettings.shared
    @ObservedObject private var settings = ClockSettings.shared
    @ObservedObject private var alerts = AlertCenter.shared
    @State private var editingAlarm: AlarmDraft?
    @State private var editingPreset: PresetDraft?

    /// 動作確認用：起動オプション --test-preset-editor のとき、「しっかり」の複製の編集画面を開く
    static var openPresetEditorForTest = false

    struct AlarmDraft: Identifiable { let id = UUID(); var alarm: Alarm; var isNew: Bool }
    struct PresetDraft: Identifiable { let id = UUID(); var preset: AlertPreset; var isNew: Bool }

    var body: some View {
        Form {
            Section {
                if fs.alarms.isEmpty {
                    Text(L("アラームはまだありません。", "No alarms yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(fs.alarms) { alarm in alarmRow(alarm) }
                Button {
                    editingAlarm = AlarmDraft(alarm: Self.newAlarm(), isNew: true)
                } label: {
                    Label(L("アラームを追加", "Add Alarm"), systemImage: "plus")
                }
            } header: {
                InfoHeader(L("アラーム", "Alarms"),
                           info: L("Mac がスリープしている間は鳴りません。スリープから戻ったときに「鳴らなかったアラーム」として知らせます。",
                       "Alarms can’t ring while the Mac is asleep. When it wakes up, you’ll be told about any missed alarms."))
            }

            Section {
                LabeledContent(L("通知の許可", "Permission")) {
                    HStack(spacing: 6) {
                        Image(systemName: alerts.notificationPermission == .allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(alerts.notificationPermission == .allowed ? Color.green : Color.orange)
                        Text(alerts.notificationPermission.label)
                    }
                }
                HStack {
                    if alerts.notificationPermission == .notAsked {
                        Button(L("許可を求める", "Request Permission")) { alerts.requestNotificationPermission() }
                    }
                    Button(L("システム設定の「通知」を開く", "Open Notification Settings")) { alerts.openNotificationSettings() }
                    Spacer()
                    Button(L("状態を確かめ直す", "Check Again")) { alerts.refreshNotificationStatus() }
                }
            } header: {
                InfoHeader(L("通知センター", "Notification Center"),
                           info: L("通知センターに出すには、macOS で Clockpane の通知が許可されている必要があります。許可されていなくても、音と時計での表示は出ます。集中モード（おやすみモードなど）の間は、通知のバナーは出ません。",
                       "To appear in Notification Center, Clockpane’s notifications must be allowed in macOS. Sound and the clock display work even without it. Banners don’t appear while a Focus (such as Do Not Disturb) is on."))
            }
            .onAppear { alerts.refreshNotificationStatus() }

            Section {
                ForEach(fs.orderedPresets) { preset in presetRow(preset) }
                Button {
                    let base = fs.preset(AlertPreset.standardID)
                    editingPreset = PresetDraft(preset: AlertPreset(id: "custom-\(UUID().uuidString)",
                                                                    name: L("新しい知らせ方", "New Alert Style"),
                                                                    style: base.style), isNew: true)
                } label: {
                    Label(L("知らせ方を追加", "Add Alert Style"), systemImage: "plus")
                }
            } header: {
                InfoHeader(L("知らせ方", "Alert Styles"),
                           info: L("☆をクリックするとお気に入りになり、選ぶときの一覧の先頭に出ます。最初から入っている知らせ方は、「複製して編集」で自分用に変えられます。",
                       "Click ☆ to make an alert style a favorite so it appears first in lists. Built-in styles can be customized with “Duplicate and Edit”."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if Self.openPresetEditorForTest {
                Self.openPresetEditorForTest = false
                let strong = fs.preset(AlertPreset.strongID)
                editingPreset = PresetDraft(preset: AlertPreset(id: "custom-\(UUID().uuidString)",
                                                                name: L("\(strong.name)のコピー", "\(strong.name) Copy"),
                                                                style: strong.style), isNew: true)
            }
        }
        .sheet(item: $editingAlarm) { draft in
            AlarmEditorView(alarm: draft.alarm, isNew: draft.isNew)
        }
        .sheet(item: $editingPreset) { draft in
            PresetEditorView(preset: draft.preset, isNew: draft.isNew)
        }
    }

    /// 新しいアラームは「次のちょうどの時刻」を初期値にする
    private static func newAlarm() -> Alarm {
        let hour = (Calendar.current.component(.hour, from: Date()) + 1) % 24
        return Alarm(hour: hour, minute: 0)
    }

    private func alarmRow(_ alarm: Alarm) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { alarm.enabled }, set: { fs.setAlarm(alarm.id, enabled: $0) }))
                .labelsHidden()
                .toggleStyle(.switch)
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.timeText).font(.system(size: 22, weight: .medium)).monospacedDigit()
                    .foregroundStyle(alarm.enabled ? .primary : .secondary)
                Text("\(alarm.displayLabel) · \(alarm.repeatSummary) · \(fs.presetLabel(alarm.presetID))")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(L("編集", "Edit")) { editingAlarm = AlarmDraft(alarm: alarm, isNew: false) }
            Button {
                fs.deleteAlarm(alarm.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L("削除", "Delete"))
        }
    }

    private func presetRow(_ preset: AlertPreset) -> some View {
        HStack(spacing: 10) {
            Button {
                fs.toggleFavorite(preset.id)
            } label: {
                Image(systemName: fs.isFavorite(preset.id) ? "star.fill" : "star")
                    .foregroundStyle(fs.isFavorite(preset.id) ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(fs.isFavorite(preset.id) ? L("お気に入りから外す", "Remove from Favorites") : L("お気に入りに追加", "Add to Favorites"))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                Text(Self.summary(preset.style)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(L("試す", "Test")) { AlertCenter.shared.preview(preset.style, title: preset.name) }
            if preset.isBuiltin {
                Button(L("複製して編集", "Duplicate and Edit")) {
                    editingPreset = PresetDraft(preset: AlertPreset(id: "custom-\(UUID().uuidString)",
                                                                    name: L("\(preset.name)のコピー", "\(preset.name) Copy"),
                                                                    style: preset.style), isNew: true)
                }
            } else {
                Button(L("編集", "Edit")) { editingPreset = PresetDraft(preset: preset, isNew: false) }
                Button {
                    fs.deletePreset(preset.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L("削除", "Delete"))
            }
        }
    }

    /// 知らせ方の短い説明（例：「光る・Glass 50% 3回・通知」）
    static func summary(_ s: AlertStyle) -> String {
        var parts: [String] = []
        if s.showOnClock { parts.append(s.blink ? L("点滅", "blink") : L("光る", "glow")) }
        if s.enlarge { parts.append(L("拡大", "enlarge")) }
        if s.playSound {
            let times = s.soundRepeat == 0 ? L("止めるまで", "until stopped") : L("\(s.soundRepeat)回", "×\(s.soundRepeat)")
            parts.append("\(s.soundName) \(Int((s.volume * 100).rounded()))% \(times)")
        }
        if s.notify { parts.append(L("通知", "notification")) }
        if s.speak { parts.append(L("読み上げ", "speech")) }
        return parts.isEmpty ? L("知らせない", "no alert") : parts.joined(separator: L("・", ", "))
    }
}

// MARK: - アラームの編集

struct AlarmEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fs = FeatureSettings.shared
    @State private var alarm: Alarm
    @State private var time: Date
    let isNew: Bool

    init(alarm: Alarm, isNew: Bool) {
        _alarm = State(initialValue: alarm)
        _time = State(initialValue: Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute,
                                                          second: 0, of: Date()) ?? Date())
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    DatePicker(L("時刻", "Time"), selection: $time, displayedComponents: .hourAndMinute)
                    TextField(L("名前", "Name"), text: $alarm.label, prompt: Text(L("例：会議", "e.g. Meeting")))
                }
                Section(L("繰り返し", "Repeat")) {
                    Picker("", selection: $alarm.repeatKind) {
                        ForEach(RepeatKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if alarm.repeatKind == .custom {
                        HStack(spacing: 6) {
                            ForEach(1...7, id: \.self) { day in weekdayButton(day) }
                        }
                    }
                }
                Section(L("知らせ方", "Alert")) {
                    PresetPicker(title: L("知らせ方", "Alert style"), selection: $alarm.presetID)
                    Stepper(L("スヌーズ：\(alarm.snoozeMinutes)分", "Snooze: \(alarm.snoozeMinutes) min"),
                            value: $alarm.snoozeMinutes, in: 1...30)
                    Button(L("この知らせ方を試す", "Test This Alert")) {
                        AlertCenter.shared.preview(fs.preset(alarm.presetID).style,
                                                   title: alarm.label.isEmpty ? nil : alarm.label)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(L("キャンセル", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? L("追加", "Add") : L("保存", "Save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(alarm.repeatKind == .custom && alarm.weekdays.isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 470)
    }

    private func weekdayButton(_ day: Int) -> some View {
        let on = alarm.weekdays.contains(day)
        return Button {
            if on { alarm.weekdays.removeAll { $0 == day } } else { alarm.weekdays.append(day) }
        } label: {
            Text(Alarm.weekdaySymbols[day - 1])
                .frame(minWidth: 34, minHeight: 24)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(Capsule().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        alarm.hour = c.hour ?? alarm.hour
        alarm.minute = c.minute ?? alarm.minute
        alarm.enabled = true
        fs.saveAlarm(alarm)
        if fs.preset(alarm.presetID).style.notify { AlertCenter.shared.requestNotificationPermissionIfNeeded() }
        dismiss()
    }
}

// MARK: - 知らせ方の編集

struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var fs = FeatureSettings.shared
    @State private var preset: AlertPreset
    let isNew: Bool

    init(preset: AlertPreset, isNew: Bool) {
        _preset = State(initialValue: preset)
        self.isNew = isNew
    }

    private var trimmedName: String { preset.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            // 縦に長くならないよう2列に並べる
            HStack(alignment: .top, spacing: 0) {
                Form {
                    Section {
                        TextField(L("名前", "Name"), text: $preset.name)
                    }
                    AlertStyleEditor(style: $preset.style, part: .lookAndSound)
                }
                .formStyle(.grouped)
                Form {
                    AlertStyleEditor(style: $preset.style, part: .speechAndOther)
                }
                .formStyle(.grouped)
            }

            Divider()
            HStack {
                Button(L("キャンセル", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("試す", "Test")) { AlertCenter.shared.preview(preset.style, title: trimmedName) }
                Spacer()
                Button(isNew ? L("追加", "Add") : L("保存", "Save")) {
                    preset.name = trimmedName
                    fs.savePreset(preset)
                    if preset.style.notify { AlertCenter.shared.requestNotificationPermissionIfNeeded() }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
        .frame(width: 780, height: 640)
    }
}

// MARK: - タイマー・時報のタブ

struct TimerSettingsView: View {
    @ObservedObject private var fs = FeatureSettings.shared
    @ObservedObject private var timer = TimerModel.shared
    @ObservedObject private var settings = ClockSettings.shared
    @State private var customMinutes = FeatureSettings.shared.lastTimerMinutes

    var body: some View {
        Form {
            Section {
                if timer.isRunning { runningRow }
                if let next = timer.waitingNextLabel {
                    HStack {
                        Text(L("ポモドーロ：次の区切りを待っています", "Pomodoro: waiting for the next session"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(next) { timer.startWaitingNext() }
                        Button(L("終える", "End")) { timer.stop() }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(TimerPresets.minutes, id: \.self) { m in
                        Button(TimerPresets.label(m)) { timer.startTimer(minutes: m) }
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Stepper(L("\(customMinutes)分", "\(customMinutes) min"), value: $customMinutes, in: 1...240)
                    Spacer()
                    Button(L("この時間で開始", "Start")) { timer.startTimer(minutes: customMinutes) }
                }
                PresetPicker(title: L("終わったときの知らせ方", "Alert when done"), selection: $fs.timerPresetID)
            } header: {
                InfoHeader(L("タイマー", "Timer"),
                           info: L("動いている間は、アナログ時計の縁に残りの時間が輪で、時計の下に残り時間が出ます。時計の中心のメニューからも開始・一時停止できます。",
                       "While running, the remaining time appears as a ring on the analog clock and as text below the clock. You can also start or pause it from the clock’s center menu."))
            }

            Section {
                Stepper(L("作業：\(fs.pomodoroWork)分", "Focus: \(fs.pomodoroWork) min"), value: $fs.pomodoroWork, in: 5...90, step: 5)
                Stepper(L("短い休憩：\(fs.pomodoroShort)分", "Short break: \(fs.pomodoroShort) min"), value: $fs.pomodoroShort, in: 1...30)
                Stepper(L("長い休憩：\(fs.pomodoroLong)分", "Long break: \(fs.pomodoroLong) min"), value: $fs.pomodoroLong, in: 5...60, step: 5)
                Stepper(L("長い休憩は \(fs.pomodoroLongEvery) 回ごと", "Long break every \(fs.pomodoroLongEvery) sessions"),
                        value: $fs.pomodoroLongEvery, in: 2...8)
                Toggle(L("自動で次へ進む", "Continue automatically"), isOn: $fs.pomodoroAutoContinue)
                Button(L("ポモドーロを開始", "Start Pomodoro")) { timer.startPomodoro() }
            } header: {
                InfoHeader(L("ポモドーロ", "Pomodoro"),
                           info: L("作業と休憩を交互にくり返します（初期値は作業25分・休憩5分、4回ごとに15分の長い休憩）。知らせ方はタイマーと同じものを使います。",
                       "Alternates focus and break sessions (default: 25-min focus, 5-min break, 15-min long break every 4 sessions). Uses the same alert style as the timer."))
            }

            Section {
                Picker(L("時報", "Chime"), selection: $fs.chimeMode) {
                    ForEach(ChimeMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if fs.chimeMode != .off {
                    SoundPicker(title: L("音の種類", "Sound"), name: $fs.chimeSound, volume: fs.chimeVolume)
                    PercentSlider(title: L("音量", "Volume"), value: $fs.chimeVolume)
                    Toggle(L("時計を一瞬光らせる", "Flash the clock"), isOn: $fs.chimeFlash)
                    Toggle(L("夜は鳴らさない", "Quiet at night"), isOn: $fs.chimeQuiet)
                    if fs.chimeQuiet {
                        HStack {
                            Picker(L("鳴らさない時間", "Quiet from"), selection: $fs.chimeQuietStart) {
                                ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                            }
                            Picker(L("〜", "to"), selection: $fs.chimeQuietEnd) {
                                ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                            }
                        }
                    }
                    Button(L("試す", "Test")) {
                        AlertCenter.shared.chime(sound: fs.chimeSound, volume: fs.chimeVolume, flash: fs.chimeFlash)
                    }
                }
            } header: {
                Text(L("時報", "Hourly Chime"))
            }
        }
        .formStyle(.grouped)
    }

    private var runningRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                let r = Int(timer.remaining(at: context.date).rounded(.up))
                Text("\(timer.phase?.icon ?? "") \(timer.phase?.label ?? "")  \(String(format: "%d:%02d", r / 60, r % 60))")
                    .font(.system(size: 20, weight: .medium)).monospacedDigit()
                if timer.isPaused { Text(L("一時停止中", "Paused")).foregroundStyle(.secondary) }
                Spacer()
                if timer.isPaused {
                    Button(L("再開", "Resume")) { timer.resume() }
                } else {
                    Button(L("一時停止", "Pause")) { timer.pause() }
                }
                if timer.isPomodoro { Button(L("次へ", "Skip")) { timer.skip() } }
                Button(L("止める", "Stop")) { timer.stop() }
            }
        }
    }
}

// MARK: - 予定・世界時計・締切のタブ

struct MoreSettingsView: View {
    @ObservedObject private var fs = FeatureSettings.shared
    @ObservedObject private var calendar = CalendarService.shared
    @ObservedObject private var settings = ClockSettings.shared
    @State private var citySearch = ""

    var body: some View {
        Form {
            calendarSection
            worldSection
            deadlineSection
        }
        .formStyle(.grouped)
    }

    // MARK: カレンダー

    private var calendarSection: some View {
        Section {
            Toggle(L("次の予定を時計の下に表示する", "Show the next event below the clock"), isOn: Binding(
                get: { fs.calendarEnabled },
                set: { on in
                    if on {
                        calendar.requestAccess { granted in fs.calendarEnabled = granted }
                    } else {
                        fs.calendarEnabled = false
                    }
                }))
            if calendar.isDenied {
                Text(L("カレンダーへのアクセスが許可されていません。システム設定 →「プライバシーとセキュリティ」→「カレンダー」で Clockpane を許可してください。",
                       "Calendar access isn’t allowed. Allow Clockpane in System Settings → Privacy & Security → Calendars."))
                    .font(.caption).foregroundStyle(.red)
            }
            if fs.calendarEnabled {
                Picker(L("表示する範囲", "Show when within"), selection: $fs.calendarShowWithinHours) {
                    ForEach([1, 3, 6, 12, 24], id: \.self) { Text(L("\($0)時間以内", "\($0) hours")).tag($0) }
                }
                Picker(L("始まる前に知らせる", "Alert before start"), selection: $fs.calendarAlertMinutes) {
                    Text(L("知らせない", "Off")).tag(0)
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text(L("\($0)分前", "\($0) min before")).tag($0) }
                }
                if fs.calendarAlertMinutes > 0 {
                    PresetPicker(title: L("知らせ方", "Alert style"), selection: $fs.calendarPresetID)
                }
                if let ev = calendar.nextEvent {
                    LabeledContent(L("次の予定", "Next event")) {
                        Text("\(ev.title)  \(Self.dateTime(ev.start))").foregroundStyle(.secondary)
                    }
                    if let place = ev.location {
                        LabeledContent(L("場所", "Location")) { Text(place).foregroundStyle(.secondary) }
                    }
                    if let host = ev.linkHost {
                        LabeledContent(L("会議のリンク", "Meeting link")) {
                            HStack {
                                Text(host).foregroundStyle(.secondary)
                                Button(L("参加する", "Join")) { calendar.joinNextEvent() }
                            }
                        }
                    }
                } else {
                    Text(L("24時間以内の予定はありません。", "No events in the next 24 hours."))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
                InfoHeader(L("カレンダーの予定", "Calendar"),
                           info: L("Mac の「カレンダー」アプリの予定を使います（Google カレンダーなどを同期していれば、それも含まれます）。終日の予定は表示しません。",
                   "Uses events from the Mac’s Calendar app (including synced accounts such as Google Calendar). All-day events aren’t shown."))
            }
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = ClockSettings.shared.locale
        f.setLocalizedDateFormatFromTemplate(ClockSettings.shared.use24Hour ? "MMMdEEEHHmm" : "MMMdEEEhmma")
        return f.string(from: date)
    }

    // MARK: 世界時計

    private var worldSection: some View {
        Section {
            ForEach($fs.worldCities) { $city in
                HStack {
                    TextField(L("名前", "Name"), text: $city.name)
                        .frame(maxWidth: 180)
                    Text(CityCatalog.offsetText(city.timeZoneID)).foregroundStyle(.secondary).font(.caption)
                    Spacer()
                    Button {
                        fs.worldCities.removeAll { $0.id == city.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            if fs.worldCities.count < 4 {
                TextField(L("都市を探す（例：ロンドン、New York）", "Search for a city (e.g. London, Tokyo)"), text: $citySearch)
                ForEach(CityCatalog.search(citySearch).prefix(6)) { entry in
                    HStack {
                        Text(entry.displayName)
                        Text(CityCatalog.offsetText(entry.timeZoneID)).foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button(L("追加", "Add")) {
                            fs.worldCities.append(WorldCity(timeZoneID: entry.timeZoneID, name: entry.displayName))
                            citySearch = ""
                        }
                    }
                }
            }
        } header: {
                InfoHeader(L("世界時計", "World Clock"),
                           info: L("時計の下に、ほかの都市の時刻を4つまで表示します。日付が違うときは（翌日）（前日）と出ます。",
                   "Shows the time in up to 4 other cities below the clock, with (+1 day) or (−1 day) when the date differs."))
            }
    }

    // MARK: 締切

    private var deadlineSection: some View {
        Section {
            Toggle(L("一番近い締切を時計の下に表示する", "Show the nearest deadline below the clock"), isOn: $fs.showDeadline)
            ForEach($fs.deadlines) { $deadline in
                HStack {
                    TextField(L("名前", "Name"), text: $deadline.title)
                    DatePicker("", selection: $deadline.date, displayedComponents: .date)
                        .labelsHidden()
                    Button {
                        fs.deadlines.removeAll { $0.id == deadline.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                let date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                fs.deadlines.append(Deadline(title: L("締切", "Deadline"), date: date))
            } label: {
                Label(L("締切を追加", "Add Deadline"), systemImage: "plus")
            }
        } header: {
                InfoHeader(L("締切までのカウントダウン", "Deadline Countdown"),
                           info: L("今日以降で一番近い締切を「あと○日」と表示します。過ぎた締切は表示しません。",
                   "Shows the nearest upcoming deadline as “in N days”. Past deadlines aren’t shown."))
            }
    }
}

// MARK: - 都市の一覧（世界時計で使う）

enum CityCatalog {
    struct Entry: Identifiable, Hashable {
        let ja: String
        let en: String
        let timeZoneID: String
        var id: String { "\(en)|\(timeZoneID)" }
        var displayName: String { ClockSettings.shared.isJapanese ? ja : en }
    }

    static let common: [Entry] = [
        Entry(ja: "東京", en: "Tokyo", timeZoneID: "Asia/Tokyo"),
        Entry(ja: "ソウル", en: "Seoul", timeZoneID: "Asia/Seoul"),
        Entry(ja: "北京", en: "Beijing", timeZoneID: "Asia/Shanghai"),
        Entry(ja: "上海", en: "Shanghai", timeZoneID: "Asia/Shanghai"),
        Entry(ja: "台北", en: "Taipei", timeZoneID: "Asia/Taipei"),
        Entry(ja: "香港", en: "Hong Kong", timeZoneID: "Asia/Hong_Kong"),
        Entry(ja: "シンガポール", en: "Singapore", timeZoneID: "Asia/Singapore"),
        Entry(ja: "バンコク", en: "Bangkok", timeZoneID: "Asia/Bangkok"),
        Entry(ja: "デリー", en: "Delhi", timeZoneID: "Asia/Kolkata"),
        Entry(ja: "ドバイ", en: "Dubai", timeZoneID: "Asia/Dubai"),
        Entry(ja: "モスクワ", en: "Moscow", timeZoneID: "Europe/Moscow"),
        Entry(ja: "ロンドン", en: "London", timeZoneID: "Europe/London"),
        Entry(ja: "パリ", en: "Paris", timeZoneID: "Europe/Paris"),
        Entry(ja: "ベルリン", en: "Berlin", timeZoneID: "Europe/Berlin"),
        Entry(ja: "アムステルダム", en: "Amsterdam", timeZoneID: "Europe/Amsterdam"),
        Entry(ja: "チューリッヒ", en: "Zurich", timeZoneID: "Europe/Zurich"),
        Entry(ja: "ジュネーブ", en: "Geneva", timeZoneID: "Europe/Zurich"),
        Entry(ja: "ローマ", en: "Rome", timeZoneID: "Europe/Rome"),
        Entry(ja: "マドリード", en: "Madrid", timeZoneID: "Europe/Madrid"),
        Entry(ja: "ストックホルム", en: "Stockholm", timeZoneID: "Europe/Stockholm"),
        Entry(ja: "カイロ", en: "Cairo", timeZoneID: "Africa/Cairo"),
        Entry(ja: "ヨハネスブルグ", en: "Johannesburg", timeZoneID: "Africa/Johannesburg"),
        Entry(ja: "ニューヨーク", en: "New York", timeZoneID: "America/New_York"),
        Entry(ja: "ワシントン", en: "Washington, D.C.", timeZoneID: "America/New_York"),
        Entry(ja: "ボストン", en: "Boston", timeZoneID: "America/New_York"),
        Entry(ja: "トロント", en: "Toronto", timeZoneID: "America/Toronto"),
        Entry(ja: "シカゴ", en: "Chicago", timeZoneID: "America/Chicago"),
        Entry(ja: "デンバー", en: "Denver", timeZoneID: "America/Denver"),
        Entry(ja: "ロサンゼルス", en: "Los Angeles", timeZoneID: "America/Los_Angeles"),
        Entry(ja: "サンフランシスコ", en: "San Francisco", timeZoneID: "America/Los_Angeles"),
        Entry(ja: "バンクーバー", en: "Vancouver", timeZoneID: "America/Vancouver"),
        Entry(ja: "ホノルル", en: "Honolulu", timeZoneID: "Pacific/Honolulu"),
        Entry(ja: "サンパウロ", en: "São Paulo", timeZoneID: "America/Sao_Paulo"),
        Entry(ja: "メキシコシティ", en: "Mexico City", timeZoneID: "America/Mexico_City"),
        Entry(ja: "シドニー", en: "Sydney", timeZoneID: "Australia/Sydney"),
        Entry(ja: "メルボルン", en: "Melbourne", timeZoneID: "Australia/Melbourne"),
        Entry(ja: "オークランド", en: "Auckland", timeZoneID: "Pacific/Auckland"),
        Entry(ja: "協定世界時（UTC）", en: "UTC", timeZoneID: "UTC"),
    ]

    /// 名前（日本語・英語）か、タイムゾーンの名前で探す。空なら主な都市を出す
    static func search(_ query: String) -> [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        let hits = common.filter { $0.ja.lowercased().contains(q) || $0.en.lowercased().contains(q) }
        let known = Set(common.map(\.timeZoneID))
        let extra = TimeZone.knownTimeZoneIdentifiers
            .filter { !known.contains($0) && $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(q) }
            .map { id -> Entry in
                let city = (id.split(separator: "/").last.map(String.init) ?? id).replacingOccurrences(of: "_", with: " ")
                return Entry(ja: city, en: city, timeZoneID: id)
            }
        return hits + extra
    }

    /// 例：「−9時間」「+0時間」（いまの時間帯との差）
    static func offsetText(_ id: String) -> String {
        guard let tz = TimeZone(identifier: id) else { return "" }
        let now = Date()
        let diff = Double(tz.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)) / 3600
        let value = diff == diff.rounded() ? String(format: "%+d", Int(diff)) : String(format: "%+.1f", diff)
        return L("\(value)時間", "\(value) h")
    }
}
