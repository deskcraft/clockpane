import AppKit
import SwiftUI

/// アプリから deskcraft のサイトへ案内するリンク
enum AppLinks {
    static let website = URL(string: "https://github.com/deskcraft/clockpane")!
    static let issues = URL(string: "https://github.com/deskcraft/clockpane/issues")!
    static let organization = URL(string: "https://github.com/deskcraft")!
    static let latestRelease = URL(string: "https://github.com/deskcraft/clockpane/releases/latest")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/deskcraft/clockpane/releases/latest")!

    static func open(_ url: URL) { NSWorkspace.shared.open(url) }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 「Clockpane について」の画面（版番号の下にリンクを出す）
    static func showAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let text = NSMutableAttributedString(
            string: L("デスクトップに置く時計アプリ\n", "A desktop clock for your Mac\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        text.append(NSAttributedString(string: "github.com/deskcraft/clockpane",
                                       attributes: [.font: NSFont.systemFont(ofSize: 11), .link: website]))
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        text.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: text.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: text])
    }
}

/// 「アップデートを確認」：押したときだけ GitHub に最新版の番号を問い合わせる（利用者の情報は送らない）
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(String)
        case available(String)
        case failed
    }

    @Published private(set) var state: State = .idle

    var message: String? {
        switch state {
        case .idle: return nil
        case .checking: return L("確認しています…", "Checking…")
        case .upToDate(let v): return L("最新版です（\(v)）", "You’re up to date (\(v))")
        case .available(let v): return L("新しい版 \(v) があります", "Version \(v) is available")
        case .failed: return L("確認できませんでした。ネットワークの接続を確かめてください。", "Couldn’t check. Please check your network connection.")
        }
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        var request = URLRequest(url: AppLinks.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let latest: String? = {
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else { return nil }
                return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            }()
            DispatchQueue.main.async {
                guard let latest else { self.state = .failed; return }
                self.state = Self.isNewer(latest, than: AppLinks.appVersion) ? .available(latest) : .upToDate(AppLinks.appVersion)
            }
        }.resume()
    }

    /// 版番号（例：1.0.10 と 1.0.9）を数字として比べる
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// 設定の「一般」とヘルプに出す、版番号・アップデートの確認・リンクの欄
struct AboutLinksView: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject private var settings = ClockSettings.shared
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Clockpane 版 \(AppLinks.appVersion)", "Clockpane version \(AppLinks.appVersion)"))
                Spacer()
                if case .available = updater.state {
                    Button(L("ダウンロードのページを開く", "Open Download Page")) { AppLinks.open(AppLinks.latestRelease) }
                        .buttonStyle(.borderedProminent)
                }
                Button(L("アップデートを確認", "Check for Updates")) { updater.check() }
                    .disabled(updater.state == .checking)
            }
            if let message = updater.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(updater.state == .failed ? Color.red : .secondary)
            }
            HStack(spacing: 14) {
                Button(L("ウェブサイト", "Website")) { AppLinks.open(AppLinks.website) }
                Button(L("不具合の報告・要望", "Report an Issue")) { AppLinks.open(AppLinks.issues) }
                Button(L("deskcraft のほかのツール", "More deskcraft Tools")) { AppLinks.open(AppLinks.organization) }
            }
            .buttonStyle(.link)
        }
    }
}
