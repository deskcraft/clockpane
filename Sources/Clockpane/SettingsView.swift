import SwiftUI
import ServiceManagement

/// 設定画面：左に項目の一覧、右にその中身（どの画面もなるべくスクロールせずに収まるように分けている）
struct SettingsView: View {
    @ObservedObject var settings: ClockSettings
    @ObservedObject private var nav = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, selection: Binding(get: { nav.tab }, set: { if let t = $0 { nav.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .padding(.vertical, 3)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            Group {
                switch nav.tab {
                case .clock: ClockPage(settings: settings)
                case .design: DesignPage(settings: settings)
                case .alarms: AlarmSettingsView()
                case .timer: TimerSettingsView()
                case .more: MoreSettingsView()
                case .general: GeneralPage(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 740)
    }
}

// MARK: - 共通

let settingsTileBackground = LinearGradient(
    colors: [Color(red: 0.33, green: 0.36, blue: 0.55), Color(red: 0.55, green: 0.42, blue: 0.62)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

/// 指定した枠に収まるように縮小したライブプレビュー
struct DesignPreview: View {
    @ObservedObject var settings: ClockSettings
    let palette: ClockPalette
    let box: CGFloat

    var body: some View {
        let unit = ClockSettings.contentSize(style: settings.style, base: 1,
                                             use24Hour: settings.use24Hour, showSeconds: settings.showSeconds)
        LiveClockView(settings: settings,
                      sizeOverride: box / max(unit.width, unit.height),
                      paletteOverride: palette)
    }
}

/// デザインの1枚：クリックで選択、右上の☆でお気に入り、右クリックで編集など
struct DesignTile: View {
    @ObservedObject var settings: ClockSettings
    let design: DesignItem

    var body: some View {
        let favorite = settings.isFavorite(design.id)
        let selected = settings.designID == design.id
        VStack(spacing: 3) {
            DesignPreview(settings: settings, palette: design.palette, box: 64)
                .frame(width: 80, height: 80)
                .background(settingsTileBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.green : .clear, lineWidth: 3))
                .overlay(alignment: .topTrailing) {
                    Button {
                        settings.toggleFavorite(design.id)
                    } label: {
                        Image(systemName: favorite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(favorite ? Color.yellow : Color.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 1.5)
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(favorite ? L("お気に入りから外す", "Remove from Favorites") : L("お気に入りに追加", "Add to Favorites"))
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { settings.designID = design.id }
            Text(design.name).font(.caption.weight(selected ? .bold : .regular))
                .lineLimit(1).truncationMode(.tail)
            Text(design.caption).font(.system(size: 9))
                .foregroundStyle(design.isCustom ? Color.accentColor : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: 88)
        .contextMenu {
            Button(L("このデザインにする", "Use This Design")) { settings.designID = design.id }
            Button(favorite ? L("お気に入りから外す", "Remove from Favorites") : L("お気に入りに追加", "Add to Favorites")) { settings.toggleFavorite(design.id) }
            Divider()
            Button(L("これをもとに新しく作る…", "New Design Based on This…")) { AppWindows.shared.createDesign(basedOn: design) }
            if let id = design.customID, let custom = settings.customDesign(id) {
                Button(L("編集…", "Edit…")) { AppWindows.shared.showEditor(design: custom, isNew: false) }
                Button(L("複製", "Duplicate")) {
                    settings.saveCustom(CustomDesign(name: settings.uniqueName(custom.name), palette: custom.palette))
                }
                Divider()
                Button(L("削除…", "Delete…"), role: .destructive) { confirmDelete(custom) }
            }
        }
    }

    private func confirmDelete(_ custom: CustomDesign) {
        let alert = NSAlert()
        alert.messageText = L("「\(custom.name)」を削除しますか？", "Delete “\(custom.name)”?")
        alert.informativeText = L("削除したデザインは元に戻せません。", "A deleted design can’t be restored.")
        alert.addButton(withTitle: L("削除", "Delete"))
        alert.addButton(withTitle: L("キャンセル", "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            settings.deleteCustom(custom.id)
        }
    }
}

// MARK: - 時計

struct ClockPage: View {
    @ObservedObject var settings: ClockSettings

    /// 選んでいるデザインとお気に入り（重なりなし、最大5つ）
    private var quickDesigns: [DesignItem] {
        var items = [settings.currentDesign]
        for d in settings.orderedDesigns where settings.isFavorite(d.id) && !items.contains(where: { $0.id == d.id }) {
            items.append(d)
        }
        return Array(items.prefix(5))
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    DesignPreview(settings: settings, palette: settings.currentDesign.palette, box: 86)
                        .frame(width: 100, height: 100)
                        .background(settingsTileBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("ローカル時刻", "Local Time")).font(.title2.bold())
                        Text(TimeZone.current.localizedName(for: .standard, locale: settings.locale) ?? TimeZone.current.identifier)
                            .foregroundStyle(.secondary)
                        Text("\(settings.style.displayName)・\(settings.currentDesign.name)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section(L("表示形式", "Display")) {
                Picker(L("時計の種類", "Clock Style"), selection: $settings.style) {
                    ForEach(ClockStyle.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(L("24時間表示", "24-Hour Time"), isOn: $settings.use24Hour)
                    .disabled(settings.style == .analog)
                    .help(L("デジタル表示のときに使われます", "Used for the digital clock"))
                Toggle(settings.style == .analog ? L("秒針", "Second Hand") : L("秒を表示", "Show Seconds"), isOn: $settings.showSeconds)
                Toggle(L("曜日と日付", "Date and Weekday"), isOn: $settings.showDate)
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(quickDesigns) { d in DesignTile(settings: settings, design: d) }
                    Spacer(minLength: 8)
                    Button(L("すべてのデザインを表示…", "Show All Designs…")) { SettingsNavigation.shared.tab = .design }
                        .padding(.top, 28)
                }
            } header: {
                InfoHeader(L("デザイン（選んでいるものとお気に入り）", "Design (current and favorites)"),
                           info: L("ここには選んでいるデザインと、☆を付けたお気に入りが出ます。ほかのデザインを選んだり、新しく作ったりするときは「すべてのデザインを表示…」を押してください。",
                                   "This shows the current design and your ☆ favorites. To choose another design or create a new one, click “Show All Designs…”."))
            }

            Section(L("外観", "Appearance")) {
                LabeledContent(L("サイズ", "Size")) {
                    HStack {
                        Slider(value: $settings.size, in: 80...500, step: 10)
                        Text("\(Int(settings.size)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                LabeledContent(L("不透明度", "Opacity")) {
                    HStack {
                        Slider(value: $settings.opacity, in: 0.15...1.0)
                        Text("\(Int((settings.opacity * 100).rounded())) %").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - デザイン

struct DesignPage: View {
    @ObservedObject var settings: ClockSettings

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 100), spacing: 10)], spacing: 12) {
                    ForEach(settings.orderedDesigns) { d in DesignTile(settings: settings, design: d) }
                }
                .padding(.vertical, 4)
                .animation(.easeInOut(duration: 0.25), value: settings.favoriteDesigns)
                HStack {
                    Button {
                        AppWindows.shared.createDesign(basedOn: settings.currentDesign)
                    } label: {
                        Label(L("選んでいるデザインをもとに新しく作る…", "New Design Based on Current…"), systemImage: "plus")
                    }
                    Spacer()
                    if let id = settings.currentDesign.customID, let custom = settings.customDesign(id) {
                        Button(L("編集…", "Edit…")) { AppWindows.shared.showEditor(design: custom, isNew: false) }
                    }
                }
            } header: {
                InfoHeader(L("デザイン", "Design"),
                           info: L("クリックでそのデザインに変わります。☆をクリックするとお気に入りになり、一覧とメニューの先頭に出ます。右クリックで、編集・複製・削除や、そのデザインをもとに新しく作ることができます。",
                                   "Click a design to use it. Click ☆ to make it a favorite so it appears first here and in the menus. Right-click a design to edit, duplicate, delete, or create a new design based on it."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 一般

struct GeneralPage: View {
    @ObservedObject var settings: ClockSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("常に手前に表示", "Always on Top"), isOn: $settings.alwaysOnTop)
                Toggle(L("ドラッグで時計を移動", "Drag to Move Clock"), isOn: $settings.dragEnabled)
                Button(L("位置をリセット", "Reset Position")) {
                    NotificationCenter.default.post(name: .resetClockPosition, object: nil)
                }
            } header: {
                InfoHeader(L("位置", "Position"),
                           info: L("時計の中心にマウスを乗せると丸いつまみが出ます。つまみをクリック（または右クリック）するとメニューが出ます。「ドラッグで時計を移動」がオンのときは、つまみをドラッグして時計を動かせます。つまみ以外の場所のクリックは、時計を素通りして下のウインドウに届きます。「常に手前に表示」か「ドラッグで時計を移動」がオンのときは時計がほかのウインドウより手前に出て、どちらもオフのときはデスクトップ（ウインドウの裏）に表示されます。",
                                   "Hover over the center of the clock to show a round handle. Click (or right-click) it to open a menu. When “Drag to Move Clock” is on, drag the handle to move the clock. Clicks anywhere else pass through the clock to the window below. When “Always on Top” or “Drag to Move Clock” is on, the clock appears above other windows; when both are off, it sits on the desktop behind your windows."))
            }

            Section(L("一般", "General")) {
                Picker(L("言語", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L("Dockにアイコンを表示", "Show Icon in Dock"), isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { AppWindows.shared.updateActivationPolicy() }
                    .help(L("オフにすると、設定画面とヘルプを閉じたあとはメニューバーのアイコンだけになります", "When off, only the menu bar icon remains after you close Settings and Help"))
                Toggle(L("ログイン時に起動", "Open at Login"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            if newValue { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section(L("Clockpane について", "About Clockpane")) {
                AboutLinksView()
            }

            Section {
                HStack {
                    Button(L("ヘルプを表示", "Show Help")) { AppWindows.shared.showHelp() }
                    Spacer()
                    Button(L("Clockpane を終了", "Quit Clockpane")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
