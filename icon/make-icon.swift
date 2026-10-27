// Draws the app icon: a miniature AKP03E (3x2 keys, three buttons, three knobs)
// on the macOS rounded-square plate. Usage: swift icon/make-icon.swift out.png
import AppKit

let S: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gray(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(gray: w, alpha: a) }

func linear(_ path: CGPath, _ top: CGColor, _ bottom: CGColor) {
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let box = path.boundingBox
    let g = CGGradient(colorsSpace: rgb, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: box.midX, y: box.maxY),
                           end: CGPoint(x: box.midX, y: box.minY), options: [])
    ctx.restoreGState()
}

func stroke(_ path: CGPath, _ c: CGColor, _ w: CGFloat) {
    ctx.saveGState(); ctx.addPath(path); ctx.setStrokeColor(c); ctx.setLineWidth(w)
    ctx.strokePath(); ctx.restoreGState()
}

// Plate: Apple's 824 pt grid inside 1024, with a soft drop shadow.
let plateRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let plate = CGPath(roundedRect: plateRect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: gray(0, 0.45))
ctx.addPath(plate); ctx.setFillColor(gray(0.16)); ctx.fillPath()
ctx.restoreGState()
linear(plate, gray(0.25), gray(0.11))
stroke(plate, gray(1, 0.10), 4)

// Keys: the starter page's colours, 3 columns x 2 rows.
let key: CGFloat = 140, gap: CGFloat = 26
let buttonD: CGFloat = 64, buttonGap: CGFloat = 60
let keysHeight = 2 * key + gap
// Centre the whole layout (keys + button row) on the plate.
let keysX: CGFloat = 168
let keysTop = plateRect.midY + (keysHeight + buttonGap + buttonD) / 2
let palette: [UInt32] = [0x0A84FF, 0xD97757, 0xFF9F0A, 0x30D158, 0xFF453A, 0x5E5CE6]
for i in 0..<6 {
    let col = CGFloat(i % 3), row = CGFloat(i / 3)
    let r = CGRect(x: keysX + col * (key + gap), y: keysTop - key - row * (key + gap),
                   width: key, height: key)
    let p = CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: gray(0, 0.5))
    ctx.addPath(p); ctx.setFillColor(color(palette[i])); ctx.fillPath()
    ctx.restoreGState()
    // Glass: lighter top, darker bottom.
    linear(p, gray(1, 0.28), gray(0, 0.18))
    stroke(p, gray(1, 0.18), 3)
}

// Three screenless buttons under the grid.
let keysWidth = 3 * key + 2 * gap
let buttonsY = keysTop - keysHeight - buttonGap - buttonD
for i in 0..<3 {
    let cx = keysX + key / 2 + CGFloat(i) * (key + gap)
    let r = CGRect(x: cx - buttonD / 2, y: buttonsY, width: buttonD, height: buttonD)
    let p = CGPath(ellipseIn: r, transform: nil)
    linear(p, gray(0.34), gray(0.17))
    stroke(p, gray(1, 0.14), 3)
}

// Knobs: one large, two small, right of the grid.
func knob(center: CGPoint, d: CGFloat) {
    let outer = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: gray(0, 0.55))
    ctx.addEllipse(in: outer); ctx.setFillColor(gray(0.2)); ctx.fillPath()
    ctx.restoreGState()
    // Knurled rim: diagonal sheen plus grip ticks.
    linear(CGPath(ellipseIn: outer, transform: nil), gray(0.40), gray(0.12))
    ctx.saveGState()
    ctx.setStrokeColor(gray(0, 0.35)); ctx.setLineWidth(max(2, d * 0.012))
    for t in 0..<48 {
        let a = CGFloat(t) / 48 * 2 * .pi
        ctx.move(to: CGPoint(x: center.x + cos(a) * d * 0.36, y: center.y + sin(a) * d * 0.36))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * d * 0.49, y: center.y + sin(a) * d * 0.49))
    }
    ctx.strokePath()
    ctx.restoreGState()
    let cap = outer.insetBy(dx: d * 0.17, dy: d * 0.17)
    linear(CGPath(ellipseIn: cap, transform: nil), gray(0.30), gray(0.17))
    stroke(CGPath(ellipseIn: cap, transform: nil), gray(0, 0.5), d * 0.03)
    // Pointer notch.
    let notch = CGRect(x: center.x - d * 0.025, y: center.y + d * 0.14, width: d * 0.05, height: d * 0.14)
    ctx.addPath(CGPath(roundedRect: notch, cornerWidth: d * 0.025, cornerHeight: d * 0.025, transform: nil))
    ctx.setFillColor(gray(1, 0.75)); ctx.fillPath()
}
// The large knob sits beside the keys, the small pair level with the buttons.
let knobsX = keysX + keysWidth + 50
let rightEdge = plateRect.maxX - 64
let bigD = rightEdge - knobsX
knob(center: CGPoint(x: knobsX + bigD / 2, y: keysTop - keysHeight / 2), d: bigD)
let smallD = (bigD - 22) / 2
let smallY = buttonsY + buttonD / 2
knob(center: CGPoint(x: knobsX + smallD / 2, y: smallY), d: smallD)
knob(center: CGPoint(x: rightEdge - smallD / 2, y: smallY), d: smallD)

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.png")
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
