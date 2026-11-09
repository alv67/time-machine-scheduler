// Genera Resources/AppIcon-1024.png: icona in stile Time Machine (squircle chiara,
// cerchio turchese, freccia/orologio bianchi) con una lancetta arancione regolabile.
// Uso: swift Tools/make-icon.swift Resources/AppIcon-1024.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon-1024.png"
let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

let white = NSColor.white
let orange = NSColor(srgbRed: 1.00, green: 0.33, blue: 0.10, alpha: 1)
let tealTop = NSColor(srgbRed: 0.42, green: 0.86, blue: 0.81, alpha: 1)
let tealBottom = NSColor(srgbRed: 0.11, green: 0.64, blue: 0.59, alpha: 1)

let body = CGRect(x: 90, y: 90, width: 844, height: 844)
let squircle = CGPath(roundedRect: body, cornerWidth: 215, cornerHeight: 215, transform: nil)

// Ombra
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 32, color: NSColor.black.withAlphaComponent(0.30).cgColor)
ctx.addPath(squircle)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()

// Corpo chiaro, come l'icona Time Machine
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let bodyGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1).cgColor,
        NSColor(srgbRed: 0.84, green: 0.85, blue: 0.88, alpha: 1).cgColor,
    ] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    bodyGradient,
    start: CGPoint(x: 512, y: 944),
    end: CGPoint(x: 512, y: 80),
    options: []
)
ctx.restoreGState()

let center = CGPoint(x: 512, y: 512)

// Cerchio turchese
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - 330, y: center.y - 330, width: 660, height: 660))
ctx.clip()
let tealGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [tealTop.cgColor, tealBottom.cgColor] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    tealGradient,
    start: CGPoint(x: 512, y: 842),
    end: CGPoint(x: 512, y: 182),
    options: []
)
ctx.restoreGState()

// Anello bianco con freccia: spessori dell'icona Time Machine
let ringRadius: CGFloat = 230
let ringWidth: CGFloat = 40
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 16, color: NSColor.black.withAlphaComponent(0.20).cgColor)
ctx.setStrokeColor(white.cgColor)
ctx.setLineWidth(ringWidth)
ctx.setLineCap(.round)
ctx.addArc(center: center, radius: ringRadius,
           startAngle: 230 * .pi / 180,
           endAngle: 170 * .pi / 180,
           clockwise: false)
ctx.strokePath()

// Punta grande e arrotondata, come nell'icona Time Machine
let arrowAngle = 170.0 * Double.pi / 180
let arrowPoint = CGPoint(x: center.x + ringRadius * cos(arrowAngle),
                         y: center.y + ringRadius * sin(arrowAngle))
let tangent = CGVector(dx: -sin(arrowAngle), dy: cos(arrowAngle))
let normal = CGVector(dx: cos(arrowAngle), dy: sin(arrowAngle))
let arrow = CGMutablePath()
let arrowBack = CGPoint(x: arrowPoint.x - tangent.dx * 24, y: arrowPoint.y - tangent.dy * 24)
arrow.move(to: CGPoint(x: arrowPoint.x + tangent.dx * 76, y: arrowPoint.y + tangent.dy * 76))
arrow.addLine(to: CGPoint(x: arrowBack.x + normal.dx * 64, y: arrowBack.y + normal.dy * 64))
arrow.addLine(to: CGPoint(x: arrowBack.x - normal.dx * 64, y: arrowBack.y - normal.dy * 64))
arrow.closeSubpath()
ctx.setFillColor(white.cgColor)
ctx.addPath(arrow)
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(arrow)
ctx.setStrokeColor(white.cgColor)
ctx.setLineWidth(14)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.restoreGState()

func hand(angleDegrees: Double, length: CGFloat, width: CGFloat, color: NSColor) {
    let radians = angleDegrees * Double.pi / 180
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + length * cos(radians), y: center.y + length * sin(radians)))
    ctx.strokePath()
}

// Lancetta ore bianca (come Time Machine) + lancetta rossa regolabile col pomello
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: NSColor.black.withAlphaComponent(0.18).cgColor)
hand(angleDegrees: 90, length: 156, width: 38, color: white)

let minuteAngle = 300.0 * Double.pi / 180
let knobCenter = CGPoint(x: center.x + 230 * cos(minuteAngle), y: center.y + 230 * sin(minuteAngle))
hand(angleDegrees: 300, length: 230, width: 38, color: orange)
ctx.setFillColor(orange.cgColor)
ctx.fillEllipse(in: CGRect(x: knobCenter.x - 44, y: knobCenter.y - 44, width: 88, height: 88))
ctx.setFillColor(white.cgColor)
ctx.fillEllipse(in: CGRect(x: knobCenter.x - 15, y: knobCenter.y - 15, width: 30, height: 30))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Icona scritta in \(output)")
