#!/usr/bin/env swift

// Regenerates Dictora's app icon set from a single master artwork.
//
//     swift Scripts/generate-app-icon.swift
//
// The master (Design/AppIcon-master.png) is a 1024×1024 full-bleed square.
// iOS uses it as-is — the system applies the mask. macOS expects the artwork to
// carry its own shape, so each macOS size is drawn into Apple's icon grid: an
// 824/1024 body clipped to a squircle, leaving the surrounding transparent
// margin the Dock and Finder rely on for consistent optical sizing.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Apple's macOS icon grid

/// Fraction of the canvas occupied by the icon body (824 of 1024).
let bodyScale = 824.0 / 1024.0

/// Superellipse exponent. n = 5 over an 824pt square matches the curvature of a
/// 185pt continuous corner radius, which is the shape macOS icons use. A plain
/// `CGPath(roundedRect:)` would give circular corners and read subtly wrong at
/// large sizes.
let squircleExponent = 5.0

// MARK: - Paths

let repoRoot = URL(fileURLWithPath: CommandLine.arguments.first.map {
    URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent().path
} ?? FileManager.default.currentDirectoryPath)

let catalogURL = repoRoot.appending(path: "Dictora/Resources/Assets.xcassets")
let masterURL = repoRoot.appending(path: "Design/AppIcon-master.png")
let iconSetURL = catalogURL.appending(path: "AppIcon.appiconset")
/// The same mark, for use inside the app — onboarding and the window headers.
let logoSetURL = catalogURL.appending(path: "Logo.imageset")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard FileManager.default.fileExists(atPath: masterURL.path) else {
    fail("master artwork not found at \(masterURL.path)")
}
guard
    let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
    let master = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("could not decode \(masterURL.lastPathComponent)")
}
guard master.width == master.height else {
    fail("master artwork must be square, got \(master.width)×\(master.height)")
}

for directory in [iconSetURL, logoSetURL] {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

// MARK: - Drawing

func makeSquirclePath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 720
    let power = 2.0 / squircleExponent

    for step in 0...steps {
        let angle = 2 * Double.pi * Double(step) / Double(steps)
        let cosine = cos(angle)
        let sine = sin(angle)
        let point = CGPoint(
            x: center.x + halfWidth * copysign(pow(abs(cosine), power), cosine),
            y: center.y + halfHeight * copysign(pow(abs(sine), power), sine)
        )
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }

    path.closeSubpath()
    return path
}

/// - Parameter opaque: When true the bitmap carries no alpha channel at all.
///   App Store validation rejects iOS icons that have one, even if every pixel
///   is fully opaque.
func makeContext(pixels: Int, opaque: Bool) -> CGContext {
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: alphaInfo.rawValue
    ) else {
        fail("could not create a \(pixels)px bitmap context")
    }
    context.interpolationQuality = .high
    return context
}

func write(_ image: CGImage, named filename: String, in directory: URL) {
    let url = directory.appending(path: filename)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fail("could not write \(filename)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not finalise \(filename)") }
    print("  \(filename) — \(image.width)×\(image.height)")
}

/// Full-bleed, opaque. Used for iOS, where the system applies the mask and
/// rejects alpha in app icons.
func renderFullBleed(pixels: Int, named filename: String, in directory: URL) {
    let context = makeContext(pixels: pixels, opaque: true)
    let rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
    context.draw(master, in: rect)

    guard let image = context.makeImage() else { fail("render failed for \(filename)") }
    write(image, named: filename, in: directory)
}

/// Clipped to the macOS icon grid, with a transparent margin.
func renderMacIcon(pixels: Int, named filename: String) {
    let context = makeContext(pixels: pixels, opaque: false)
    let canvas = Double(pixels)
    let body = canvas * bodyScale
    let bodyRect = CGRect(
        x: (canvas - body) / 2,
        y: (canvas - body) / 2,
        width: body,
        height: body
    )

    context.addPath(makeSquirclePath(in: bodyRect))
    context.clip()
    context.draw(master, in: bodyRect)

    guard let image = context.makeImage() else { fail("render failed for \(filename)") }
    write(image, named: filename, in: iconSetURL)
}

// MARK: - Catalog

/// macOS entries, as (point size, scale). Two entries can share a pixel size
/// (16@2x and 32@1x are both 32px) but each slot gets its own file so the
/// catalog stays explicit and easy to re-render.
let macSlots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

func macFilename(points: Int, scale: Int) -> String {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    return "icon_\(points)x\(points)\(suffix).png"
}

let iosFilename = "icon_ios_1024.png"

/// Nominal point size of the in-app logo. Larger than any current use, so the
/// 3x asset is never upscaled.
let logoPoints = 128

print("Rendering app icons from \(masterURL.lastPathComponent)…")
renderFullBleed(pixels: 1024, named: iosFilename, in: iconSetURL)
for slot in macSlots {
    renderMacIcon(pixels: slot.points * slot.scale, named: macFilename(points: slot.points, scale: slot.scale))
}

print("Rendering the in-app logo…")
for scale in 1...3 {
    let suffix = scale == 1 ? "" : "@\(scale)x"
    renderFullBleed(
        pixels: logoPoints * scale,
        named: "logo_\(logoPoints)\(suffix).png",
        in: logoSetURL
    )
}

// MARK: - Contents.json

var entries: [String] = [
    """
      {
        "filename" : "\(iosFilename)",
        "idiom" : "universal",
        "platform" : "ios",
        "size" : "1024x1024"
      }
    """,
]

for slot in macSlots {
    entries.append(
        """
          {
            "filename" : "\(macFilename(points: slot.points, scale: slot.scale))",
            "idiom" : "mac",
            "scale" : "\(slot.scale)x",
            "size" : "\(slot.points)x\(slot.points)"
          }
        """
    )
}

let contents = """
{
  "images" : [
\(entries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

try contents.write(to: iconSetURL.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("  AppIcon.appiconset/Contents.json — \(macSlots.count + 1) entries")

let logoEntries = (1...3).map { scale in
    let suffix = scale == 1 ? "" : "@\(scale)x"
    return """
      {
        "filename" : "logo_\(logoPoints)\(suffix).png",
        "idiom" : "universal",
        "scale" : "\(scale)x"
      }
    """
}

let logoContents = """
{
  "images" : [
\(logoEntries.joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

try logoContents.write(to: logoSetURL.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("  Logo.imageset/Contents.json — 3 entries")
