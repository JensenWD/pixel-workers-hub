// Draws Support/AppIcon.icns from the panel's own sprites: a worker typing at their desk on panel paper.
// Run with `make icon` (or `swift scripts/make-icon.swift`) from the repository root.
import AppKit
import JavaScriptCore

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let context = JSContext()!
context.exceptionHandler = { _, error in fatalError("sprites.js: \(error?.toString() ?? "?")") }
context.evaluateScript("var window = {}")
context.evaluateScript(try! String(contentsOf: root.appendingPathComponent("Web/sprites.js"), encoding: .utf8))
// One still frame: the first of each two-frame loop, with the desk's shared pieces written out in place.
let svg = context.evaluateScript("""
  (() => {
    const { spriteDefs, cast, agentScene } = window.Sprites
    const defs = {}
    spriteDefs.replace(/<g id="px-([a-z0-9]+)">(.*?)<\\/g>/g, (_, id, body) => { defs[id] = body })
    const look = cast(['pixel-workers-hub']).get('pixel-workers-hub')
    return agentScene('working', look)
      .replace(/<use href="#px-[a-z0-9]+" class="px-b[^"]*"\\/>/g, '')
      .replace(/<g class="px-b[^"]*">.*?<\\/g>/g, '')
      .replace(/<use href="#px-([a-z0-9]+)"[^>]*\\/>/g, (_, id) => defs[id])
      .replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" width="360" height="260" ')
  })()
""")!.toString()!
guard let scene = NSImage(data: Data(svg.utf8)) else { fatalError("Couldn't read the sprite as SVG") }

func icon(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .none
    // Apple's icon grid: an 824-point rounded square centred on the 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.95, blue: 0.9, alpha: 1), ending: NSColor(srgbRed: 0.91, green: 0.87, blue: 0.78, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSColor(srgbRed: 0.16, green: 0.17, blue: 0.15, alpha: 1).setStroke()
    shape.lineWidth = 10
    shape.stroke()
    // 36×26 sprite pixels at 20 points each.
    scene.draw(in: NSRect(x: 152, y: 252, width: 720, height: 520))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! icon(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try! icon(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Support/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
try! icon(512).write(to: root.appendingPathComponent("Support/icon.png"))
print(iconutil.terminationStatus == 0 ? "Wrote Support/AppIcon.icns" : "iconutil failed")
