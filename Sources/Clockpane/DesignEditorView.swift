import SwiftUI

/// カスタムデザインの編集画面（左にプレビュー、右に各部の設定）
struct DesignEditorView: View {
    @ObservedObject var settings: ClockSettings
    @State var draft: CustomDesign
    let isNew: Bool
    let close: () -> Void
    @State private var previewStyle: ClockStyle = .analog

    private let tileBackground = LinearGradient(
        colors: [Color(red: 0.33, green: 0.36, blue: 0.55), Color(red: 0.55, green: 0.42, blue: 0.62)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HStack(spacing: 0) {
            previewPane
            Divider()
            editorForm
        }
        .frame(width: 860, height: 720)
    }

    // MARK: 左：プレビューと保存

    private var previewPane: some View {
        VStack(spacing: 14) {
            Picker("", selection: $previewStyle) {
                ForEach(ClockStyle.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let unit = ClockSettings.contentSize(style: previewStyle, base: 1,
                                                 use24Hour: settings.use24Hour, showSeconds: settings.showSeconds)
            LiveClockView(settings: settings,
                          sizeOverride: 220 / max(unit.width, unit.height),
                          paletteOverride: draft.palette,
                          styleOverride: previewStyle)
                .frame(width: 250, height: 250)
                .background(tileBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text(L("背景の紫はプレビュー用です。デスクトップでは壁紙の上に表示されます。", "The purple background is only for the preview. On the desktop, the clock appears over your wallpaper."))
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            if trimmedName.isEmpty {
                Text(L("名前を入力してください", "Enter a name")).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button(L("キャンセル", "Cancel")) { close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(isNew ? L("保存して使う", "Save and Use") : L("上書き保存", "Save Changes")) {
                    var saved = draft
                    saved.name = trimmedName
                    settings.saveCustom(saved)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    // MARK: 右：各部の設定

    private var editorForm: some View {
        Form {
            Section(L("名前", "Name")) {
                TextField(L("デザインの名前", "Design name"), text: $draft.name)
            }

            Section(L("縁", "Rim")) {
                slider(L("太さ", "Thickness"), $draft.palette.rimWidth, 0...0.12, zeroLabel: L("なし", "None"))
                colorRow(L("色（左上）", "Color (top left)"), $draft.palette.rimLight)
                colorRow(L("色（右下）", "Color (bottom right)"), $draft.palette.rimDark)
                Toggle(L("内側に点の飾り", "Dotted inner ring"), isOn: $draft.palette.beads)
            }

            Section(L("盤面（背景）", "Face (Background)")) {
                colorRow(L("色（上）", "Color (top)"), $draft.palette.faceTop)
                colorRow(L("色（下）", "Color (bottom)"), $draft.palette.faceBottom)
                Button(L("下の色を上の色と同じにする", "Make bottom color same as top")) { draft.palette.faceBottom = draft.palette.faceTop }
            }

            Section(L("目盛り", "Marks")) {
                colorRow(L("色", "Color"), $draft.palette.tick)
                slider(L("時の目盛りの太さ", "Hour mark thickness"), $draft.palette.hourTickWidth, 0...0.06, zeroLabel: L("なし", "None"))
                slider(L("時の目盛りの長さ", "Hour mark length"), Binding(
                    get: { draft.palette.hourTickOuter - draft.palette.hourTickInner },
                    set: { draft.palette.hourTickInner = draft.palette.hourTickOuter - $0 }), 0.03...0.35)
                Picker(L("分の目盛り", "Minute marks"), selection: $draft.palette.minuteMarks) {
                    ForEach(MinuteMarkStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section(L("数字", "Numbers")) {
                Picker(L("種類", "Type"), selection: $draft.palette.numerals) {
                    ForEach(NumeralStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("書体", "Typeface"), selection: $draft.palette.numeralFont) {
                    ForEach(NumeralFont.allCases) { Text($0.label).tag($0) }
                }
                optionalColorRow(L("色", "Color"), $draft.palette.numeralColor, fallback: draft.palette.tick)
                slider(L("大きさ", "Size"), $draft.palette.numeralScale, 0.6...1.8)
                slider(L("位置（中心からの距離）", "Position (distance from center)"), $draft.palette.numeralRadius, 0.40...0.82)
            }

            Section(L("針", "Hands")) {
                colorRow(L("時針・分針の色", "Hour and minute hand color"), $draft.palette.hand)
                Picker(L("形", "Shape"), selection: $draft.palette.handShape) {
                    ForEach(HandShape.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                slider(L("太さ", "Thickness"), $draft.palette.handWeight, 0.4...2.0)
                colorRow(L("秒針の色", "Second hand color"), $draft.palette.second)
                Picker(L("秒の表し方", "Seconds display"), selection: $draft.palette.secondStyle) {
                    ForEach(SecondStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker(L("表示する内容", "Content"), selection: $draft.palette.dateContent) {
                    ForEach(DateContent.allCases) { Text($0.label).tag($0) }
                }
                Picker(L("位置", "Position"), selection: $draft.palette.datePosition) {
                    ForEach(DatePosition.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                optionalColorRow(L("色", "Color"), $draft.palette.dateColor, fallback: draft.palette.tick.opacity(0.85))
            } header: {
                Text(L("日付・曜日", "Date and Weekday"))
            } footer: {
                Text(L("日付を出すかどうかは、設定画面の「曜日と日付」で切り替えます。位置はアナログ時計のときに使われます。", "Whether the date is shown is set with “Date and Weekday” in Settings. Position applies to the analog clock."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("その他", "Other")) {
                Toggle(L("影を付ける（壁紙の上で見やすくなります）", "Drop shadow (easier to see on wallpaper)"), isOn: $draft.palette.dropShadow)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: 部品

    private func colorRow(_ title: String, _ value: Binding<RGBA>) -> some View {
        ColorPicker(title, selection: Binding(get: { value.wrappedValue.color },
                                              set: { value.wrappedValue = RGBA($0) }),
                    supportsOpacity: true)
    }

    /// 「目盛りと同じ色」を選べる色の行（nil = 同じ色）
    private func optionalColorRow(_ title: String, _ value: Binding<RGBA?>, fallback: RGBA) -> some View {
        HStack {
            Toggle(L("目盛りと同じ色", "Same as marks"), isOn: Binding(
                get: { value.wrappedValue == nil },
                set: { value.wrappedValue = $0 ? nil : fallback }))
            Spacer()
            ColorPicker(title, selection: Binding(get: { (value.wrappedValue ?? fallback).color },
                                                  set: { value.wrappedValue = RGBA($0) }),
                        supportsOpacity: true)
                .disabled(value.wrappedValue == nil)
                .fixedSize()
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        zeroLabel: String? = nil) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(value.wrappedValue <= 0.0001 && zeroLabel != nil
                     ? zeroLabel! : "\(Int((value.wrappedValue / range.upperBound * 100).rounded()))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .frame(width: 260)
        }
    }
}
