import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/Assets/AppIcon-source.png")
let size = 1024
let scale = CGFloat(size)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Unable to create graphics context")
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x * scale, y: y * scale)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func drawRounded(_ box: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: box, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
}

func drawLinearGradient(in path: CGPath, colors: [CGColor], start: CGPoint, end: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
}

func drawRadialGlow(center: CGPoint, radius: CGFloat, inner: CGColor, outer: CGColor) {
    let gradient = CGGradient(colorsSpace: colorSpace, colors: [inner, outer] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius * scale,
        options: .drawsAfterEndLocation
    )
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Flip into a familiar top-left coordinate system for easier composition.
context.translateBy(x: 0, y: scale)
context.scaleBy(x: 1, y: -1)

let iconBounds = rect(0.09, 0.09, 0.82, 0.82)
let iconPath = CGPath(roundedRect: iconBounds, cornerWidth: 0.145 * scale, cornerHeight: 0.145 * scale, transform: nil)

drawLinearGradient(
    in: iconPath,
    colors: [
        color(0.03, 0.34, 0.98),
        color(0.04, 0.58, 1.0),
        color(0.01, 0.18, 0.72)
    ],
    start: point(0.18, 0.12),
    end: point(0.84, 0.88)
)

context.saveGState()
context.addPath(iconPath)
context.clip()
drawRadialGlow(center: point(0.28, 0.22), radius: 0.42, inner: color(0.62, 0.9, 1, 0.58), outer: color(0.62, 0.9, 1, 0))
drawRadialGlow(center: point(0.74, 0.75), radius: 0.38, inner: color(0.0, 0.05, 0.32, 0.42), outer: color(0.0, 0.05, 0.32, 0))
context.restoreGState()

// Back layer suggests "floating on all desktops" without becoming a busy illustration.
context.setShadow(offset: CGSize(width: 0, height: 26), blur: 30, color: color(0, 0.06, 0.26, 0.26))
drawRounded(rect(0.255, 0.295, 0.49, 0.47), radius: 0.078, fill: color(0.78, 0.9, 1, 0.28))
context.setShadow(offset: .zero, blur: 0, color: nil)

// Main translucent checklist surface.
context.setShadow(offset: CGSize(width: 0, height: 22), blur: 34, color: color(0, 0.04, 0.26, 0.36))
drawRounded(rect(0.22, 0.245, 0.56, 0.52), radius: 0.086, fill: color(0.96, 0.99, 1, 0.9))
context.setShadow(offset: .zero, blur: 0, color: nil)

let cardPath = CGPath(roundedRect: rect(0.22, 0.245, 0.56, 0.52), cornerWidth: 0.086 * scale, cornerHeight: 0.086 * scale, transform: nil)
context.saveGState()
context.addPath(cardPath)
context.clip()
drawRadialGlow(center: point(0.34, 0.29), radius: 0.34, inner: color(1, 1, 1, 0.9), outer: color(1, 1, 1, 0))
drawRadialGlow(center: point(0.68, 0.72), radius: 0.32, inner: color(0.55, 0.76, 1, 0.22), outer: color(0.55, 0.76, 1, 0))
context.restoreGState()

context.addPath(cardPath)
context.setStrokeColor(color(1, 1, 1, 0.7))
context.setLineWidth(6)
context.strokePath()

// Checklist rows: keep them chunky so they survive Launchpad/Dock sizes.
let rowColor = color(0.18, 0.31, 0.55, 0.26)
let rowY: [CGFloat] = [0.37, 0.5, 0.63]
for y in rowY {
    drawRounded(rect(0.44, y, 0.27, 0.032), radius: 0.016, fill: rowColor)
}

let smallCircleStroke = color(0.16, 0.27, 0.46, 0.48)
for y in [CGFloat(0.386), CGFloat(0.646)] {
    context.setStrokeColor(smallCircleStroke)
    context.setLineWidth(15)
    context.strokeEllipse(in: rect(0.3, y - 0.03, 0.064, 0.064))
}

// Primary symbol.
context.setShadow(offset: CGSize(width: 0, height: 13), blur: 18, color: color(0.0, 0.18, 0.65, 0.34))
drawRounded(rect(0.275, 0.455, 0.13, 0.13), radius: 0.065, fill: color(0.0, 0.48, 1.0, 1))
drawRadialGlow(center: point(0.3, 0.475), radius: 0.13, inner: color(0.44, 0.88, 1, 0.6), outer: color(0.44, 0.88, 1, 0))
context.setShadow(offset: .zero, blur: 0, color: nil)

let check = CGMutablePath()
check.move(to: point(0.306, 0.522))
check.addLine(to: point(0.335, 0.552))
check.addLine(to: point(0.378, 0.486))
context.addPath(check)
context.setStrokeColor(color(1, 1, 1, 1))
context.setLineWidth(18)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

// Small top-right controls echo the product UI without drawing a literal screenshot.
drawRounded(rect(0.635, 0.29, 0.047, 0.047), radius: 0.0235, fill: color(0.0, 0.48, 1.0, 0.18))
drawRounded(rect(0.695, 0.29, 0.047, 0.047), radius: 0.0235, fill: color(0.0, 0.48, 1.0, 0.12))

guard let image = context.makeImage() else {
    fatalError("Unable to create icon image")
}

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print(output.path)
