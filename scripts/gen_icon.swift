#!/usr/bin/env swift
//
// 메뉴바 아이콘 생성 스크립트
//
// macOS 입력기(IMKit) template 아이콘 규격:
//   - 순수 검정 (0,0,0) RGB + 알파 채널로만 형태 표현
//   - multi-resolution TIFF (non-square 가능)
//   - sRGB IEC61966-2.1 컬러 프로파일
//   - Info.plist에 TISIconIsTemplate=true 필요
//
// 생성 아이콘:
//   - icon_menubar.tiff : 메뉴바/팔레트용 (텍스트만, 테두리 없음)
//   - icon_ko.tiff      : 입력 소스 목록용 (텍스트 + 윤곽선 테두리)
//
// 사용법:
//   swift scripts/gen_icon.swift
//

import AppKit

// MARK: - 설정

let fontSize: CGFloat = 16
let cornerRadius: CGFloat = 3.5
let strokeWidth: CGFloat = 1.0
let strokeOpacity: CGFloat = 0.55

// 테두리 있는 아이콘 (입력 소스 목록) — 22x22 정사각 캔버스 (SVG 기준)
let borderedSize: CGFloat = 22

// 텍스트만 아이콘 (메뉴바/팔레트) — 16x16 정사각 캔버스
let textOnlySize: CGFloat = 16

enum IconStyle {
    case bordered(CGFloat)  // 윤곽선 테두리 + 텍스트 (캔버스 크기)
    case textOnly           // 텍스트만
}

let icons: [(text: String, name: String, style: IconStyle)] = [
    ("온", "icon_ko",      .textOnly),
    ("온", "icon_menubar", .textOnly),
]

// MARK: - 렌더링

func renderIcon(text: String, style: IconStyle, scale: Int) -> NSBitmapImageRep {
    let logicalW: CGFloat
    let logicalH: CGFloat

    switch style {
    case .bordered(let size):
        logicalW = size
        logicalH = size
    case .textOnly:
        logicalW = textOnlySize
        logicalH = textOnlySize
    }

    let pixelW = Int(logicalW) * scale
    let pixelH = Int(logicalH) * scale

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: logicalW, height: logicalH)

    NSGraphicsContext.saveGraphicsState()
    let gfxCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gfxCtx

    // 투명 배경
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: logicalW, height: logicalH).fill()

    if case .bordered = style {
        // 둥근 정사각형 윤곽선 (stroke only, SVG 기준 opacity 적용)
        let inset = strokeWidth / 2
        let bgRect = NSRect(x: inset, y: inset,
                            width: logicalW - strokeWidth,
                            height: logicalH - strokeWidth)
        let path = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = strokeWidth
        NSColor.black.withAlphaComponent(strokeOpacity).setStroke()
        path.stroke()
    }

    // 텍스트 — EBS Hunminjeongeum SB 우선, 미설치 시 시스템 폰트 fallback
    let font: NSFont = NSFont(name: "EBS Hunminjeongeum SB", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let strSize = str.size()
    let strOrigin = NSPoint(
        x: (logicalW - strSize.width) / 2,
        y: (logicalH - strSize.height) / 2
    )
    str.draw(at: strOrigin)

    NSGraphicsContext.restoreGraphicsState()

    // 모든 픽셀의 RGB를 순수 검정(0,0,0)으로 강제, 알파만 유지
    let ptr = rep.bitmapData!
    let bytesPerRow = rep.bytesPerRow
    for y in 0..<pixelH {
        for x in 0..<pixelW {
            let offset = y * bytesPerRow + x * 4
            let alpha = ptr[offset + 3]
            ptr[offset + 0] = 0
            ptr[offset + 1] = 0
            ptr[offset + 2] = 0
            ptr[offset + 3] = alpha
        }
    }

    return rep
}

// MARK: - 외부 명령 실행

@discardableResult
func run(_ executable: String, _ arguments: String..., quiet: Bool = false) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    if quiet { p.standardOutput = FileHandle.nullDevice }
    try! p.run()
    p.waitUntilExit()
    return p.terminationStatus == 0
}

// MARK: - Main

let scriptPath = URL(fileURLWithPath: #filePath)
let projectRoot = scriptPath
    .deletingLastPathComponent()   // scripts/
    .deletingLastPathComponent()   // project root
    .path
let resourcesDir = "\(projectRoot)/OngeulApp/Resources"
let tmpDir = NSTemporaryDirectory() + "ongeul_icons"
let srgbProfile = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"

try! FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

for icon in icons {
    let rep1x = renderIcon(text: icon.text, style: icon.style, scale: 1)
    let rep2x = renderIcon(text: icon.text, style: icon.style, scale: 2)

    let path1x = "\(tmpDir)/\(icon.name).png"
    let path2x = "\(tmpDir)/\(icon.name)@2x.png"
    try! rep1x.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path1x))
    try! rep2x.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path2x))

    let srgb1x = "\(tmpDir)/\(icon.name)_srgb.png"
    let srgb2x = "\(tmpDir)/\(icon.name)@2x_srgb.png"

    guard run("/usr/bin/sips", "-m", srgbProfile, path1x, "--out", srgb1x, quiet: true),
          run("/usr/bin/sips", "-m", srgbProfile, path2x, "--out", srgb2x, quiet: true)
    else {
        fatalError("sips failed for \(icon.name)")
    }

    let output = "\(resourcesDir)/\(icon.name).tiff"
    guard run("/usr/bin/tiffutil", "-cathidpicheck", srgb1x, srgb2x, "-out", output)
    else {
        fatalError("tiffutil failed for \(icon.name)")
    }

    let w = rep1x.pixelsWide
    let h = rep1x.pixelsHigh
    let label: String
    if case .bordered = icon.style { label = "bordered" } else { label = "text-only" }
    print("  \(icon.name).tiff (\(icon.text), \(label)) — \(w)x\(h)@1x, \(w*2)x\(h*2)@2x")
}

try? FileManager.default.removeItem(atPath: tmpDir)

print("Done → \(resourcesDir)/")
