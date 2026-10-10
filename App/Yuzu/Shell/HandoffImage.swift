import AppKit
import SwiftUI

enum HandoffImage {
    static func coworkLogo(dark: Bool, width: CGFloat) -> Image? {
        guard let image = load(name: dark ? "cowork-logo" : "cowork-logo-light") else { return nil }
        return Image(nsImage: rasterized(image, pointWidth: width))
    }

    static func codeMascot(dark: Bool, width: CGFloat = 56) -> Image? {
        guard let image = load(name: dark ? "code-input-mascot" : "code-input-mascot-light") else { return nil }
        return Image(nsImage: rasterized(image, pointWidth: width))
    }

    private static func load(name: String) -> NSImage? {
        let url =
            Bundle.main.url(forResource: name, withExtension: "svg")
            ?? Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Handoff")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func rasterized(_ image: NSImage, pointWidth: CGFloat) -> NSImage {
        guard image.size.width > 0 else { return image }
        let aspect = image.size.height / image.size.width
        let pointSize = NSSize(width: pointWidth, height: pointWidth * aspect)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = max(1, Int(ceil(pointSize.width * scale)))
        let pixelHeight = max(1, Int(ceil(pointSize.height * scale)))

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return image }

        rep.size = pointSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(origin: .zero, size: pointSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: pointSize)
        result.addRepresentation(rep)
        return result
    }
}
