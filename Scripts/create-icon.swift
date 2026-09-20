import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// Original geometric artwork. Opaque RGB, suitable for an iOS app icon.
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.06, green: 0.10, blue: 0.20, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 0.94, green: 0.94, blue: 0.88, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 205, y: 210, width: 614, height: 604), cornerWidth: 58, cornerHeight: 58, transform: nil))
context.fillPath()
context.setFillColor(CGColor(red: 0.12, green: 0.60, blue: 0.59, alpha: 1))
context.move(to: CGPoint(x: 260, y: 280)); context.addLine(to: CGPoint(x: 455, y: 570))
context.addLine(to: CGPoint(x: 580, y: 420)); context.addLine(to: CGPoint(x: 675, y: 525))
context.addLine(to: CGPoint(x: 765, y: 280)); context.closePath(); context.fillPath()
context.setFillColor(CGColor(red: 1, green: 0.65, blue: 0.20, alpha: 1))
context.fillEllipse(in: CGRect(x: 610, y: 625, width: 105, height: 105))
let url = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
