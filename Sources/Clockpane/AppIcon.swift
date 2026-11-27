import SwiftUI
import AppKit

/// アプリのアイコン（紫のタイルに Retro の時計、10時10分）
struct AppIconView: View {
    let size: CGFloat

    private static let tenTen: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 1
        c.hour = 10; c.minute = 10; c.second = 32
        return Calendar.current.date(from: c) ?? Date()
    }()

    var body: some View {
        let tile = size * 0.80   // macOS のアイコンは周囲に余白を取る
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.33, green: 0.36, blue: 0.58), Color(red: 0.58, green: 0.42, blue: 0.64)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: tile, height: tile)
                .shadow(color: .black.opacity(0.3), radius: size * 0.015, y: size * 0.01)
            AnalogClockView(date: Self.tenTen, palette: ClockDesign.retro.palette, showSeconds: true, showDate: false)
                .frame(width: tile * 0.78, height: tile * 0.78)
                .shadow(color: .black.opacity(0.35), radius: size * 0.02, y: size * 0.012)
        }
        .frame(width: size, height: size)
    }
}

enum AppIcon {
    @MainActor
    static func image(size: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: AppIconView(size: size))
        renderer.scale = 1
        return renderer.nsImage
    }

    @MainActor
    static func pngData(pixels: Int) -> Data? {
        guard let cg = ImageRenderer(content: AppIconView(size: CGFloat(pixels))).cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// 確認用：すべてのデザインのアナログ時計を1枚の画像に並べて書き出す
    @MainActor
    static func exportDesignSheet(to url: URL) {
        let view = LazyVGrid(columns: Array(repeating: GridItem(.fixed(220)), count: 4), spacing: 16) {
            ForEach(ClockDesign.allCases) { d in
                VStack {
                    AnalogClockView(date: Date(), palette: d.palette, showSeconds: true, showDate: true)
                        .frame(width: 200, height: 200)
                    Text(d.displayName).foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .background(Color(red: 0.30, green: 0.34, blue: 0.45))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let cg = renderer.cgImage,
           let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
    }

    /// iconutil 用の .iconset フォルダを書き出す
    @MainActor
    static func exportIconset(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                if let data = pngData(pixels: base * scale) {
                    try? data.write(to: dir.appendingPathComponent(name))
                }
            }
        }
    }
}
