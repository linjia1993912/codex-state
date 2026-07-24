import AppKit
import Foundation

/// 纯代码绘制应用图标，输出指定尺寸的透明背景 PNG。
/// 使用 NSBitmapImageRep 直接创建位图上下文，不依赖 NSImage.lockFocus()。
enum AppIconRenderer {
    static func draw(size: CGFloat) -> Data? {
        let pixelsWide = Int(size)
        let pixelsHigh = Int(size)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        // 设置点尺寸，确保绘制比例正确
        rep.size = NSSize(width: size, height: size)

        // 创建并保存图形上下文
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        // 清除为透明背景
        NSColor.clear.set()
        NSRect(origin: .zero, size: NSSize(width: size, height: size)).fill()

        // 圆角矩形背景（橙色渐变）
        let cornerRadius = size * 0.215
        let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        bgPath.addClip()

        let gradient = NSGradient(colors: [
            NSColor(red: 1.0, green: 0.55, blue: 0.26, alpha: 1.0),
            NSColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)
        ])
        gradient?.draw(in: rect, angle: -45)

        // 缩放比例（基于 1024×1024 设计稿）
        let s = size / 1024.0

        // 脸部
        let face = NSBezierPath(ovalIn: NSRect(x: 312 * s, y: 410 * s, width: 400 * s, height: 340 * s))
        NSColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0).setFill()
        face.fill()

        // 左耳（外白内粉）
        let leftEar = NSBezierPath()
        leftEar.move(to: NSPoint(x: 320 * s, y: 380 * s))
        leftEar.line(to: NSPoint(x: 280 * s, y: 200 * s))
        leftEar.line(to: NSPoint(x: 420 * s, y: 340 * s))
        leftEar.close()
        NSColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0).setFill()
        leftEar.fill()

        // 右耳
        let rightEar = NSBezierPath()
        rightEar.move(to: NSPoint(x: 704 * s, y: 380 * s))
        rightEar.line(to: NSPoint(x: 744 * s, y: 200 * s))
        rightEar.line(to: NSPoint(x: 604 * s, y: 340 * s))
        rightEar.close()
        NSColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0).setFill()
        rightEar.fill()

        // 左耳内层
        let leftEarInner = NSBezierPath()
        leftEarInner.move(to: NSPoint(x: 340 * s, y: 360 * s))
        leftEarInner.line(to: NSPoint(x: 310 * s, y: 240 * s))
        leftEarInner.line(to: NSPoint(x: 390 * s, y: 340 * s))
        leftEarInner.close()
        NSColor(red: 1.0, green: 0.69, blue: 0.53, alpha: 1.0).setFill()
        leftEarInner.fill()

        // 右耳内层
        let rightEarInner = NSBezierPath()
        rightEarInner.move(to: NSPoint(x: 684 * s, y: 360 * s))
        rightEarInner.line(to: NSPoint(x: 714 * s, y: 240 * s))
        rightEarInner.line(to: NSPoint(x: 634 * s, y: 340 * s))
        rightEarInner.close()
        NSColor(red: 1.0, green: 0.69, blue: 0.53, alpha: 1.0).setFill()
        rightEarInner.fill()

        // 左眼
        let leftEye = NSBezierPath(ovalIn: NSRect(x: 380 * s, y: 470 * s, width: 80 * s, height: 100 * s))
        NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).setFill()
        leftEye.fill()

        // 左眼高光
        let leftEyeHighlight = NSBezierPath(ovalIn: NSRect(x: 405 * s, y: 492 * s, width: 30 * s, height: 36 * s))
        NSColor.white.setFill()
        leftEyeHighlight.fill()

        // 右眼
        let rightEye = NSBezierPath(ovalIn: NSRect(x: 564 * s, y: 470 * s, width: 80 * s, height: 100 * s))
        NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).setFill()
        rightEye.fill()

        // 右眼高光
        let rightEyeHighlight = NSBezierPath(ovalIn: NSRect(x: 589 * s, y: 492 * s, width: 30 * s, height: 36 * s))
        NSColor.white.setFill()
        rightEyeHighlight.fill()

        // 鼻子
        let nose = NSBezierPath(ovalIn: NSRect(x: 482 * s, y: 600 * s, width: 60 * s, height: 40 * s))
        NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).setFill()
        nose.fill()

        // 嘴巴（贝塞尔曲线，控制点重合模拟二次曲线）
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: 480 * s, y: 650 * s))
        let mouthControl = NSPoint(x: 512 * s, y: 680 * s)
        mouth.curve(
            to: NSPoint(x: 544 * s, y: 650 * s),
            controlPoint1: mouthControl,
            controlPoint2: mouthControl
        )
        NSColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1.0).setStroke()
        mouth.lineWidth = 8 * s
        mouth.stroke()

        // 腮红
        let leftBlush = NSBezierPath(ovalIn: NSRect(x: 310 * s, y: 575 * s, width: 80 * s, height: 50 * s))
        NSColor(red: 1.0, green: 0.69, blue: 0.53, alpha: 0.6).setFill()
        leftBlush.fill()

        let rightBlush = NSBezierPath(ovalIn: NSRect(x: 634 * s, y: 575 * s, width: 80 * s, height: 50 * s))
        NSColor(red: 1.0, green: 0.69, blue: 0.53, alpha: 0.6).setFill()
        rightBlush.fill()

        // 直接从位图获取 PNG 数据
        return rep.representation(using: .png, properties: [:])
    }
}

// CLI 入口
@main
struct IconGen {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: CodexStateIconGen <output-dir>\n".utf8))
            exit(1)
        }
        let outputDir = args[1]
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let sizes: [(String, CGFloat)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        for (name, size) in sizes {
            guard let data = AppIconRenderer.draw(size: size) else {
                FileHandle.standardError.write(Data("failed to draw \(size)\n".utf8))
                continue
            }
            let path = "\(outputDir)/\(name)"
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}
