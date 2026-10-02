// Renders an SVG to a PNG of the given pixel size using AppKit's built-in SVG support.
// Usage: swift Scripts/render-svg.swift <input.svg> <output.png> <width> [height]
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let width = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: render-svg.swift <input.svg> <output.png> <width> [height]\n".utf8))
    exit(1)
}
let height = args.count > 4 ? Int(args[4]) ?? width : width

guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("cannot read \(args[1])\n".utf8))
    exit(1)
}
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
