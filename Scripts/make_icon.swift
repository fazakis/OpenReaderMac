import AppKit
let output = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bg = NSBezierPath(roundedRect: NSRect(x: 50,y: 50,width: 924,height: 924), xRadius: 205,yRadius:205)
NSGradient(starting: NSColor(calibratedRed: 0.16,green: 0.23,blue: 0.57,alpha: 1), ending: NSColor(calibratedRed: 0.16,green: 0.62,blue: 0.72,alpha: 1))!.draw(in: bg, angle: 45)
NSColor.white.withAlphaComponent(0.96).setFill()
let book = NSBezierPath(roundedRect: NSRect(x: 205,y: 245,width: 614,height: 540), xRadius: 52,yRadius: 52); book.fill()
NSColor(calibratedRed: 0.13,green: 0.38,blue: 0.60,alpha: 1).setStroke()
let spine=NSBezierPath();spine.move(to: NSPoint(x:512,y:290));spine.line(to:NSPoint(x:512,y:735));spine.lineWidth=15;spine.lineCapStyle = .round;spine.stroke()
for (i,height) in [60,120,190,115,70].enumerated() {
 let x=CGFloat(290+i*35);let wave=NSBezierPath();wave.move(to:NSPoint(x:x,y:515-CGFloat(height)/2));wave.line(to:NSPoint(x:x,y:515+CGFloat(height)/2));wave.lineWidth=16;wave.lineCapStyle = .round;wave.stroke()
}
for (i,width) in [165,140,165,110].enumerated() {
 let y=CGFloat(635-i*72);let line=NSBezierPath();line.move(to:NSPoint(x:565,y:y));line.line(to:NSPoint(x:CGFloat(565+width),y:y));line.lineWidth=17;line.lineCapStyle = .round;line.stroke()
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
