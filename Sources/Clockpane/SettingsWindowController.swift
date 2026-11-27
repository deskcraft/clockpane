import AppKit
import SwiftUI
import Combine

/// 設定・ヘルプのウインドウを管理する。
/// ウインドウが開いている間は通常のアプリ（Dock アイコンと画面上部のメニューあり）として振る舞い、
/// すべて閉じるとメニューバー常駐（デスクトップに時計だけ）に戻る。
final class AppWindows: NSObject, NSWindowDelegate {
    static let shared = AppWindows()
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var editorWindow: NSWindow?
    private var languageWatch: AnyCancellable?

    override init() {
        super.init()
        // 言語を切り替えたら、開いているウインドウの題名も切り替える
        languageWatch = ClockSettings.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshTitles() }
    }

    private func refreshTitles() {
        settingsWindow?.title = L("Clockpane 設定", "Clockpane Settings")
        helpWindow?.title = L("Clockpane ヘルプ", "Clockpane Help")
        if let (isNew, name) = editorTitleInfo {
            editorWindow?.title = isNew ? L("新しいデザイン", "New Design") : L("デザインを編集：\(name)", "Edit Design: \(name)")
        }
        // 通知のボタン（止める・スヌーズ・参加する）の文字も、選んだ言語で登録し直す
        AlertCenter.shared.setUpNotifications()
    }

    /// デザインの編集画面の題名を、言語を切り替えたときに作り直すための情報
    private var editorTitleInfo: (isNew: Bool, name: String)?

    /// tab を指定すると、そのタブを開いた状態で設定画面を出す
    func showSettings(tab: SettingsTab? = nil) {
        if let tab { SettingsNavigation.shared.tab = tab }
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: L("Clockpane 設定", "Clockpane Settings"),
                                        content: SettingsView(settings: .shared))
        }
        present(settingsWindow)
    }

    func showHelp() {
        if helpWindow == nil {
            helpWindow = makeWindow(title: L("Clockpane ヘルプ", "Clockpane Help"), content: HelpView())
        }
        present(helpWindow)
    }

    /// デザインの編集画面を開く（開いていれば中身を入れ替える）
    func showEditor(design: CustomDesign, isNew: Bool) {
        editorWindow?.close()
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = isNew ? L("新しいデザイン", "New Design") : L("デザインを編集：\(design.name)", "Edit Design: \(design.name)")
        editorTitleInfo = (isNew, design.name)
        w.isReleasedWhenClosed = false
        w.delegate = self
        let view = DesignEditorView(settings: .shared, draft: design, isNew: isNew,
                                    close: { [weak w] in w?.close() })
        w.contentViewController = NSHostingController(rootView: view)
        w.center()
        editorWindow = w
        present(w)
    }

    /// 標準・カスタムのどちらからでも、それをもとに新しいデザインを作る
    func createDesign(basedOn item: DesignItem) {
        let settings = ClockSettings.shared
        let name = settings.uniqueName(item.isCustom ? item.name : L("\(item.name) カスタム", "\(item.name) Custom"))
        showEditor(design: CustomDesign(name: name, palette: item.palette), isNew: true)
    }

    private func makeWindow<V: View>(title: String, content: V) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: content))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        return w
    }

    /// Dock 表示がオン、または設定・ヘルプが開いている間は通常アプリ、それ以外はメニューバー常駐
    func updateActivationPolicy(closing: NSWindow? = nil) {
        let windowsOpen = [settingsWindow, helpWindow, editorWindow].contains { w in
            guard let w, w !== closing else { return false }
            return w.isVisible
        }
        let policy: NSApplication.ActivationPolicy =
            (ClockSettings.shared.showInDock || windowsOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    private func present(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        DispatchQueue.main.async { self.updateActivationPolicy(closing: closing) }
    }
}
