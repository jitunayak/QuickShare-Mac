#!/usr/bin/env swift
//
// make-icons.swift
//
// Turns a rendered Quick Share logo (white glyph on a blue circle) into every
// icon the app needs:
//
//   * AppIcon.appiconset — the logo, cropped to the circle and masked to it, at
//     all ten sizes the asset catalog references.
//   * MenuBarIcon.imageset — a monochrome *template* of just the arrows, which
//     macOS tints to match the light/dark menu bar.
//
// Run it through scripts/make-icons.sh, which does the SVG rasterisation first.
//
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
	FileHandle.standardError.write(Data((message + "\n").utf8))
	exit(1)
}

/// An RGBA8 (premultiplied) drawing surface.
final class Canvas {
	let width: Int
	let height: Int
	let ctx: CGContext
	private let buffer: UnsafeMutableRawPointer
	private let byteCount: Int

	init(width: Int, height: Int) {
		self.width = width
		self.height = height
		let bytesPerRow = width * 4
		byteCount = bytesPerRow * height
		buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
		buffer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
		guard let context = CGContext(data: buffer,
									  width: width,
									  height: height,
									  bitsPerComponent: 8,
									  bytesPerRow: bytesPerRow,
									  space: CGColorSpaceCreateDeviceRGB(),
									  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			buffer.deallocate()
			fail("cannot create a \(width)x\(height) bitmap context")
		}
		ctx = context
	}

	var pixels: UnsafeMutablePointer<UInt8> {
		buffer.bindMemory(to: UInt8.self, capacity: byteCount)
	}

	func image() -> CGImage {
		guard let snapshot = ctx.makeImage() else { fail("cannot snapshot the bitmap context") }
		return snapshot
	}

	deinit { buffer.deallocate() }
}

func loadImage(_ path: String) -> CGImage {
	guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
		  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
		fail("cannot read an image at \(path)")
	}
	return image
}

func writePNG(_ image: CGImage, to path: String) {
	let url = URL(fileURLWithPath: path)
	guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
		fail("cannot write \(path)")
	}
	CGImageDestinationAddImage(destination, image, nil)
	guard CGImageDestinationFinalize(destination) else { fail("cannot finalize \(path)") }
	print("wrote \((path as NSString).lastPathComponent) (\(image.width)x\(image.height))")
}

/// High-quality box resample. Halving repeatedly first keeps the small sizes
/// (16px) free of the ringing a single 1024 -> 16 jump would produce.
func resample(_ image: CGImage, to size: Int) -> CGImage {
	var current = image
	while current.width > size * 2 {
		current = resampleOnce(current, to: max(size, current.width / 2))
	}
	return resampleOnce(current, to: size)
}

func resampleOnce(_ image: CGImage, to size: Int) -> CGImage {
	let canvas = Canvas(width: size, height: size)
	canvas.ctx.interpolationQuality = .high
	canvas.ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
	return canvas.image()
}

/// Clips an image to the inscribed circle, so the flat background of the
/// rendered page becomes a transparent hole around the logo.
///
/// This writes coverage by hand instead of using a `destinationIn` fill: the
/// page background is opaque white, so the mask has to touch the alpha channel
/// explicitly to punch it out.
func circleMasked(_ image: CGImage) -> CGImage {
	let w = image.width, h = image.height
	let source = Canvas(width: w, height: h)
	source.ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
	let sp = source.pixels

	let out = Canvas(width: w, height: h)
	let op = out.pixels

	let cx = Double(w) / 2
	let cy = Double(h) / 2
	// A hair inside the geometric circle: the rendered edge is anti-aliased
	// against white, and this keeps that fringe from surviving.
	let radius = Double(min(w, h)) / 2 - 0.5

	for y in 0..<h {
		for x in 0..<w {
			let i = (y * w + x) * 4
			let dx = Double(x) + 0.5 - cx
			let dy = Double(y) + 0.5 - cy
			let distance = (dx * dx + dy * dy).squareRoot()
			let coverage = min(max(radius - distance + 0.5, 0), 1)
			if coverage >= 1 {
				// Fully inside the circle: copy straight through.
				op[i]     = sp[i]
				op[i + 1] = sp[i + 1]
				op[i + 2] = sp[i + 2]
				op[i + 3] = sp[i + 3]
			} else {
				// Every channel is premultiplied, so they all scale together.
				op[i]     = UInt8((Double(sp[i])     * coverage).rounded())
				op[i + 1] = UInt8((Double(sp[i + 1]) * coverage).rounded())
				op[i + 2] = UInt8((Double(sp[i + 2]) * coverage).rounded())
				op[i + 3] = UInt8((Double(sp[i + 3]) * coverage).rounded())
			}
		}
	}
	// Anything strictly outside the circle was never written and stays clear.
	return out.image()
}

// MARK: - Arguments

let args = CommandLine.arguments
guard args.count >= 4 else {
	fail("usage: make-icons.swift <rendered-logo.png> <AppIcon.appiconset> <MenuBarIcon.imageset>")
}
let sourcePath = args[1]
let appIconDir = args[2]
let menuBarDir = args[3]

// MARK: - Crop the logo out of the rendered page

let source = loadImage(sourcePath)
let sw = source.width, sh = source.height
let scan = Canvas(width: sw, height: sh)
scan.ctx.draw(source, in: CGRect(x: 0, y: 0, width: sw, height: sh))
let sourcePixels = scan.pixels

// The circle is the only saturated part of the render, so its bounding box is
// the logo's bounding box.
var minX = sw, minY = sh, maxX = -1, maxY = -1
for y in 0..<sh {
	for x in 0..<sw {
		let i = (y * sw + x) * 4
		let r = Double(sourcePixels[i]) / 255
		let g = Double(sourcePixels[i + 1]) / 255
		let b = Double(sourcePixels[i + 2]) / 255
		let hi = max(r, max(g, b)), lo = min(r, min(g, b))
		let saturation = hi > 0 ? (hi - lo) / hi : 0
		if saturation > 0.4 && b >= r && b >= g {
			minX = min(minX, x); maxX = max(maxX, x)
			minY = min(minY, y); maxY = max(maxY, y)
		}
	}
}
guard maxX > minX, maxY > minY else { fail("no logo found in \(sourcePath)") }

let side = Double(max(maxX - minX + 1, maxY - minY + 1))
let cropRect = CGRect(x: Double(minX + maxX) / 2 - side / 2,
					  y: Double(minY + maxY) / 2 - side / 2,
					  width: side, height: side)
guard let cropped = source.cropping(to: cropRect) else { fail("cannot crop the logo") }
let logo = circleMasked(cropped)

// MARK: - App icon

// Matches the filenames in AppIcon.appiconset/Contents.json: some sizes appear
// twice (1x and 2x of different slots).
let appIconFiles: [(name: String, size: Int)] = [
	("16.png", 16),
	("32.png", 32),
	("32 1.png", 32),
	("64.png", 64),
	("128.png", 128),
	("256.png", 256),
	("256 1.png", 256),
	("512.png", 512),
	("512 1.png", 512),
	("1024.png", 1024),
]
try? FileManager.default.createDirectory(atPath: appIconDir, withIntermediateDirectories: true)
var appIconCache: [Int: CGImage] = [:]
for file in appIconFiles {
	let image = appIconCache[file.size] ?? resample(logo, to: file.size)
	appIconCache[file.size] = image
	writePNG(image, to: (appIconDir as NSString).appendingPathComponent(file.name))
}

// MARK: - Menu bar glyph

// Leaf out the blue: inside the circle the only achromatic pixels are the
// arrows, so `min(rgb) * (1 - saturation)` is their alpha.
let lw = logo.width, lh = logo.height
let glyphCanvas = Canvas(width: lw, height: lh)
glyphCanvas.ctx.draw(logo, in: CGRect(x: 0, y: 0, width: lw, height: lh))
let logoPixels = glyphCanvas.pixels

var mask = [Double](repeating: 0, count: lw * lh)
var gMinX = lw, gMinY = lh, gMaxX = -1, gMaxY = -1
for y in 0..<lh {
	for x in 0..<lw {
		let i = (y * lw + x) * 4
		guard logoPixels[i + 3] > 127 else { continue }   // outside the circle
		let r = Double(logoPixels[i]) / 255
		let g = Double(logoPixels[i + 1]) / 255
		let b = Double(logoPixels[i + 2]) / 255
		let hi = max(r, max(g, b)), lo = min(r, min(g, b))
		let saturation = hi > 0 ? (hi - lo) / hi : 0
		var a = lo * (1 - saturation)
		a = (a - 0.15) / 0.7
		a = min(max(a, 0), 1)
		mask[y * lw + x] = a
		if a > 0.35 {
			gMinX = min(gMinX, x); gMaxX = max(gMaxX, x)
			gMinY = min(gMinY, y); gMaxY = max(gMaxY, y)
		}
	}
}
guard gMaxX > gMinX, gMaxY > gMinY else { fail("no glyph found inside the logo") }

// Black glyph on transparent, ready for template rendering.
let gw = gMaxX - gMinX + 1, gh = gMaxY - gMinY + 1
let glyph = Canvas(width: gw, height: gh)
let glyphPixels = glyph.pixels
for y in 0..<gh {
	for x in 0..<gw {
		let a = mask[(gMinY + y) * lw + (gMinX + x)]
		glyphPixels[(y * gw + x) * 4 + 3] = UInt8((a * 255).rounded())
	}
}
let glyphImage = glyph.image()

/// Fits the glyph into a `max`-point box, preserving its aspect ratio.
func writeMenuBarGlyph(max maxSide: Int, to path: String) {
	let scale = Double(maxSide) / Double(max(gw, gh))
	let w = max(1, Int((Double(gw) * scale).rounded()))
	let h = max(1, Int((Double(gh) * scale).rounded()))
	let canvas = Canvas(width: w, height: h)
	canvas.ctx.interpolationQuality = .high
	canvas.ctx.draw(glyphImage, in: CGRect(x: 0, y: 0, width: w, height: h))
	writePNG(canvas.image(), to: path)
}

try? FileManager.default.createDirectory(atPath: menuBarDir, withIntermediateDirectories: true)
writeMenuBarGlyph(max: 16, to: (menuBarDir as NSString).appendingPathComponent("QuickShare.png"))
writeMenuBarGlyph(max: 32, to: (menuBarDir as NSString).appendingPathComponent("QuickShare@2x.png"))
