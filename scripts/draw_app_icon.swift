import AppKit

// A small original vector mark; render without any downloaded image assets.
let size = 1024
let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                       bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
NSColor(srgbRed: 0.09, green: 0.31, blue: 0.25, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let cream = NSColor(srgbRed: 0.99, green: 0.96, blue: 0.87, alpha: 1)
cream.setFill()
NSBezierPath(ovalIn: NSRect(x: 266, y: 454, width: 492, height: 180)).fill()
let bowl = NSBezierPath()
bowl.move(to: NSPoint(x: 236, y: 506))
bowl.line(to: NSPoint(x: 788, y: 506))
bowl.curve(to: NSPoint(x: 578, y: 248), controlPoint1: NSPoint(x: 770, y: 365), controlPoint2: NSPoint(x: 673, y: 254))
bowl.line(to: NSPoint(x: 446, y: 248))
bowl.curve(to: NSPoint(x: 236, y: 506), controlPoint1: NSPoint(x: 348, y: 254), controlPoint2: NSPoint(x: 254, y: 365))
NSColor(srgbRed: 1, green: 0.66, blue: 0.34, alpha: 1).setFill()
bowl.fill()
NSBezierPath(roundedRect: NSRect(x: 418, y: 210, width: 188, height: 42), xRadius: 21, yRadius: 21).fill()
cream.setStroke()
for x in [428.0, 512.0, 596.0] {
    let steam = NSBezierPath()
    steam.move(to: NSPoint(x: x, y: 688))
    steam.curve(to: NSPoint(x: x, y: 803), controlPoint1: NSPoint(x: x - 39, y: 726), controlPoint2: NSPoint(x: x + 39, y: 765))
    steam.lineWidth = 24
    steam.lineCapStyle = .round
    steam.stroke()
}
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: canvas.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
