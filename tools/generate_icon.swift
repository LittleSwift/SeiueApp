import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Resize the approved icon master into the seven macOS asset catalog slots.
let masterURL = URL(fileURLWithPath: "assets/branding/seiue-macos-icon.png")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("Missing icon master")
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.interpolationQuality = .high
  context.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
  let url = URL(fileURLWithPath: "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png")
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Icon export failed") }
}
print("Exported 7 macOS icon sizes from Seiue icon master")
