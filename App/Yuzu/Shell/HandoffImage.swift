import AppKit
import SwiftUI

enum HandoffImage {
    static func coworkLogo(dark: Bool) -> Image? {
        guard let image = load(name: dark ? "cowork-logo" : "cowork-logo-light") else { return nil }
        return Image(nsImage: image)
    }

    static func codeMascot(dark: Bool) -> Image? {
        guard let image = load(name: dark ? "code-input-mascot" : "code-input-mascot-light") else { return nil }
        return Image(nsImage: image)
    }

    private static func load(name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Handoff") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
