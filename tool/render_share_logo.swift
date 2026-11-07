import AppKit
import Foundation

// Render the reviewed resolution-independent contour master, not a resized PNG.
// The SVG is the single source of truth for design tools and future exports.
let document = try XMLDocument(contentsOf: URL(fileURLWithPath: "assets/brand/setkeep_share_vector.svg"))
let elements = try document.nodes(forXPath: "//*[local-name()='path']")
let scale = 4
let width = 320 * scale, height = 174 * scale
let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4,
                              bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: output)!
NSGraphicsContext.current = context
context.shouldAntialias = true
context.imageInterpolation = .high
let transform = AffineTransform(translationByX: 0, byY: CGFloat(height))
var mapping = transform
mapping.scale(x: CGFloat(scale), y: -CGFloat(scale))
for element in elements {
  let element = element as! XMLElement
  let green = element.attribute(forName: "fill")!.stringValue!.contains("brandGreen")
  let data = element.attribute(forName: "d")!.stringValue!
  let expression = try NSRegularExpression(pattern: "[MLCZ]|-?[0-9]+(?:\\.[0-9]+)?")
  let tokens = expression.matches(in: data, range: NSRange(data.startIndex..., in: data)).map {
    String(data[Range($0.range, in: data)!])
  }
  let path = NSBezierPath()
  path.windingRule = .evenOdd
  var index = 0
  func point() -> NSPoint {
    let x = Double(tokens[index])!, y = Double(tokens[index + 1])!
    index += 2
    return NSPoint(x: x, y: y)
  }
  while index < tokens.count {
    let command = tokens[index]; index += 1
    switch command {
    case "M": path.move(to: point())
    case "L": path.line(to: point())
    case "C":
      let c1 = point(), c2 = point(), end = point()
      path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
    case "Z": path.close()
    default: fatalError("Unsupported SVG command")
    }
  }
  path.transform(using: mapping)
  if green {
    let gradient = NSGradient(starting: NSColor(srgbRed: 0, green: 203.0/255, blue: 166.0/255, alpha: 1),
                              ending: NSColor(srgbRed: 0, green: 135.0/255, blue: 125.0/255, alpha: 1))!
    gradient.draw(in: path, angle: -90)
  } else {
    NSColor.white.setFill()
    path.fill()
  }
}
NSGraphicsContext.restoreGraphicsState()
try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "assets/brand/setkeep_share_lockup.png"))
print("Rendered vector master at \(width)x\(height)")
