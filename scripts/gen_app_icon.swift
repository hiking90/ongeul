#!/usr/bin/env swift
//
// 앱 아이콘 생성 스크립트
//
// design/ongeul-app-icon.svg 디자인을 프로그래밍으로 재현하여
// macOS .icns 파일을 생성한다.
//
// 디자인 요소:
//   - 한지 배경 (옛 책 색감, 그라데이션)
//   - 이중 변란 (고서 판식 테두리)
//   - 세로쓰기 "온글" (훈민정음 서체)
//   - 낙관 인장 (우하단, 온글지인)
//
// 출력:
//   OngeulApp/Resources/AppIcon.icns
//
// 사용법:
//   swift scripts/gen_app_icon.swift
//

import AppKit

// MARK: - Design Constants (512×512 기준)

let designSize: CGFloat = 512

// 배경
let cornerRadius: CGFloat = 56
let bgInset: CGFloat = 16

// 변란 (테두리)
let outerBorderInset: CGFloat = 52
let innerBorderInset: CGFloat = 62

// 텍스트
let mainFontSize: CGFloat = 152
let onCenterY: CGFloat = 185    // SVG Y좌표 (위에서 아래)
let geulCenterY: CGFloat = 345
let textCenterX: CGFloat = 256

// 낙관 (인장)
let sealOriginX: CGFloat = 388
let sealOriginY: CGFloat = 400  // SVG Y
let sealSize: CGFloat = 60
let sealFontSize: CGFloat = 18
let sealRotation: CGFloat = -2.5  // degrees

// MARK: - Colors

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

let paperLight  = rgb(0xF2, 0xE4, 0xC8)
let paperMid    = rgb(0xEB, 0xDA, 0xBC)
let paperDark   = rgb(0xE0, 0xCD, 0xA6)
let spotColor   = rgb(0xC8, 0xB4, 0x94)
let borderColor = rgb(0x5C, 0x4A, 0x36)
let dividerColor = rgb(0x6B, 0x58, 0x44)
let inkColor    = rgb(0x1E, 0x12, 0x0A, 0.88)
let sealBgColor = rgb(0xBE, 0x2E, 0x28, 0.80)
let sealStroke  = rgb(0xF0, 0xC8, 0xB4, 0.35)
let sealLine    = rgb(0xF0, 0xC8, 0xB4, 0.22)
let sealTextClr = rgb(0xF0, 0xD0, 0xC0, 0.82)

// MARK: - Coordinate Helpers

/// SVG Y (top-down) → AppKit Y (bottom-up), scale 적용
func ay(_ svgY: CGFloat, _ f: CGFloat) -> CGFloat { (designSize - svgY) * f }

/// SVG rect → AppKit rect (Y 반전 + scale)
func aRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ f: CGFloat) -> NSRect {
    NSRect(x: x * f, y: (designSize - y - h) * f, width: w * f, height: h * f)
}

// MARK: - Rendering

func renderAppIcon(pixelSize: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixelSize)
    let f = size / designSize

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

    // Clear
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    // ── 1. Shadow ──
    rgb(0x2A, 0x1A, 0x0C, 0.10).setFill()
    NSBezierPath(roundedRect: aRect(18, 22, 480, 480, f),
                 xRadius: cornerRadius * f, yRadius: cornerRadius * f).fill()

    // ── 2. Paper Background (gradient) ──
    let bgRect = aRect(bgInset, bgInset, 480, 480, f)
    let bgPath = NSBezierPath(roundedRect: bgRect,
                              xRadius: cornerRadius * f, yRadius: cornerRadius * f)

    NSGraphicsContext.saveGraphicsState()
    bgPath.addClip()
    let gradient = NSGradient(colorsAndLocations:
        (paperLight, 0.0), (paperMid, 0.35), (paperDark, 1.0))!
    gradient.draw(in: bgRect, angle: 110)
    NSGraphicsContext.restoreGraphicsState()

    // ── 3. Age Spots ──
    spotColor.withAlphaComponent(0.07).setFill()
    NSBezierPath(ovalIn: aRect(105-38, 415-32, 76, 64, f)).fill()
    spotColor.withAlphaComponent(0.05).setFill()
    NSBezierPath(ovalIn: aRect(410-28, 95-24, 56, 48, f)).fill()
    spotColor.withAlphaComponent(0.04).setFill()
    NSBezierPath(ovalIn: aRect(140-22, 110-18, 44, 36, f)).fill()

    // ── 4. Borders (변란) ──
    // Outer
    let outerRect = aRect(outerBorderInset, outerBorderInset, 408, 408, f)
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 6*f, yRadius: 6*f)
    outerPath.lineWidth = 1.6 * f
    borderColor.withAlphaComponent(0.30).setStroke()
    outerPath.stroke()

    // Inner
    let innerRect = aRect(innerBorderInset, innerBorderInset, 388, 388, f)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 4*f, yRadius: 4*f)
    innerPath.lineWidth = 0.8 * f
    borderColor.withAlphaComponent(0.18).setStroke()
    innerPath.stroke()

    // Divider (계선)
    dividerColor.withAlphaComponent(0.12).setStroke()
    let divider = NSBezierPath()
    divider.move(to: NSPoint(x: 80*f, y: ay(256, f)))
    divider.line(to: NSPoint(x: 432*f, y: ay(256, f)))
    divider.lineWidth = 0.6 * f
    divider.stroke()

    // ── 5. Text: 온글 ──
    let font: NSFont = NSFont(name: "EBS Hunminjeongeum SB", size: mainFontSize * f)
        ?? NSFont(name: "Nanum Myeongjo", size: mainFontSize * f)
        ?? NSFont(name: "AppleMyungjo", size: mainFontSize * f)
        ?? NSFont.systemFont(ofSize: mainFontSize * f, weight: .medium)

    let textAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: inkColor,
    ]

    // "온" — SVG center (256, 185)
    let onStr = NSAttributedString(string: "온", attributes: textAttrs)
    let onSz = onStr.size()
    onStr.draw(at: NSPoint(x: textCenterX*f - onSz.width/2,
                           y: ay(onCenterY, f) - onSz.height/2))

    // "글" — SVG center (256, 345)
    let geulStr = NSAttributedString(string: "글", attributes: textAttrs)
    let geulSz = geulStr.size()
    geulStr.draw(at: NSPoint(x: textCenterX*f - geulSz.width/2,
                             y: ay(geulCenterY, f) - geulSz.height/2))

    // ── 6. Seal (낙관) ──
    let cgCtx = NSGraphicsContext.current!.cgContext

    // Seal center: SVG (388+30, 400+30) = (418, 430)
    let sealCX = 418 * f
    let sealCY = ay(430, f)
    let sealW = sealSize * f

    cgCtx.saveGState()

    // Rotate around seal center
    cgCtx.translateBy(x: sealCX, y: sealCY)
    cgCtx.rotate(by: -sealRotation * .pi / 180)
    cgCtx.translateBy(x: -sealCX, y: -sealCY)

    // Seal background
    let sealRect = NSRect(x: sealCX - sealW/2, y: sealCY - sealW/2,
                          width: sealW, height: sealW)
    let sealPath = NSBezierPath(roundedRect: sealRect, xRadius: 4*f, yRadius: 4*f)
    sealBgColor.setFill()
    sealPath.fill()

    // Inner border
    let sealInner = sealRect.insetBy(dx: 4*f, dy: 4*f)
    let sealInnerPath = NSBezierPath(roundedRect: sealInner, xRadius: 2*f, yRadius: 2*f)
    sealInnerPath.lineWidth = 1.2 * f
    sealStroke.setStroke()
    sealInnerPath.stroke()

    // Cross lines
    sealLine.setStroke()
    let hLine = NSBezierPath()
    hLine.move(to: NSPoint(x: sealRect.minX + 6*f, y: sealCY))
    hLine.line(to: NSPoint(x: sealRect.maxX - 6*f, y: sealCY))
    hLine.lineWidth = 0.7 * f
    hLine.stroke()

    let vLine = NSBezierPath()
    vLine.move(to: NSPoint(x: sealCX, y: sealRect.minY + 6*f))
    vLine.line(to: NSPoint(x: sealCX, y: sealRect.maxY - 6*f))
    vLine.lineWidth = 0.7 * f
    vLine.stroke()

    // Seal characters: 지(左上) 온(右上) 인(左下) 글(右下) — 전각 2×2
    // Offsets from seal center (AppKit coords: +x=right, +y=up)
    let sealFont: NSFont = NSFont(name: "EBS Hunminjeongeum SB", size: sealFontSize * f)
        ?? NSFont.boldSystemFont(ofSize: sealFontSize * f)
    let sealTA: [NSAttributedString.Key: Any] = [
        .font: sealFont,
        .foregroundColor: sealTextClr,
    ]

    // SVG local coords → centered offset (SVG origin=top-left of 60x60):
    //   지(18,18)→(-12,+12)  온(42,18)→(+12,+12)
    //   인(18,42)→(-12,-12)  글(42,42)→(+12,-12)
    let sealChars: [(String, CGFloat, CGFloat)] = [
        ("지", -12,  12),  // 左上
        ("온",  12,  12),  // 右上
        ("인", -12, -12),  // 左下
        ("글",  12, -12),  // 右下
    ]
    for (ch, dx, dy) in sealChars {
        let s = NSAttributedString(string: ch, attributes: sealTA)
        let sz = s.size()
        s.draw(at: NSPoint(x: sealCX + dx*f - sz.width/2,
                           y: sealCY + dy*f - sz.height/2))
    }

    cgCtx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - External Command

@discardableResult
func run(_ exe: String, _ args: String..., quiet: Bool = false) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    if quiet { p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice }
    try! p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// MARK: - Main

let scriptPath = URL(fileURLWithPath: #filePath)
let projectRoot = scriptPath.deletingLastPathComponent().deletingLastPathComponent().path
let resourcesDir = "\(projectRoot)/OngeulApp/Resources"
let tmpDir = NSTemporaryDirectory() + "ongeul_app_icon"
let iconsetDir = "\(tmpDir)/AppIcon.iconset"

try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// macOS iconset 필수 크기
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

print("Rendering app icon...")
for entry in sizes {
    let rep = renderAppIcon(pixelSize: entry.pixels)
    let pngData = rep.representation(using: .png, properties: [:])!
    let path = "\(iconsetDir)/\(entry.name).png"
    try! pngData.write(to: URL(fileURLWithPath: path))
    print("  \(entry.name).png (\(entry.pixels)×\(entry.pixels))")
}

// iconutil → .icns
let icnsPath = "\(resourcesDir)/AppIcon.icns"
print("Creating .icns...")
guard run("/usr/bin/iconutil", "-c", "icns", iconsetDir, "-o", icnsPath) else {
    fatalError("iconutil failed")
}

// Cleanup
try? FileManager.default.removeItem(atPath: tmpDir)

print("Done → \(icnsPath)")
