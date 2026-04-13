#!/usr/bin/env swift

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import AppKit

let TOUCHSCREEN_VENDOR_ID: Int = 0x27c0
let TOUCHSCREEN_PRODUCT_ID: Int = 0x0859

var touchscreenMaxX: CGFloat = 16383
var touchscreenMaxY: CGFloat = 9599
var touchscreenMinX: CGFloat = 0
var touchscreenMinY: CGFloat = 0

var targetScreen: NSScreen?
var screenOffsetX: CGFloat = 0
var screenOffsetY: CGFloat = 0
var screenWidth: CGFloat = 2560
var screenHeight: CGFloat = 720

var currentX: CGFloat = 0
var currentY: CGFloat = 0
var isTouching: Bool = false
var lastClickTime: Date = Date.distantPast
let debounceInterval: TimeInterval = 0.05

var lastTouchTime: Date = Date.distantPast
var lastTouchPoint: CGPoint = .zero
let doubleClickInterval: TimeInterval = 0.3
let doubleClickDistance: CGFloat = 20.0

enum ClickMode { case moveCursorAndClick, clickInPlace }
var clickMode: ClickMode = .moveCursorAndClick

enum CaptureMode { case shared, exclusive }
var captureMode: CaptureMode = .exclusive

func convertToScreenCoordinates(rawX: Int, rawY: Int) -> CGPoint {
    let normalizedX = (CGFloat(rawX) - touchscreenMinX) / (touchscreenMaxX - touchscreenMinX)
    let normalizedY = (CGFloat(rawY) - touchscreenMinY) / (touchscreenMaxY - touchscreenMinY)
    return CGPoint(x: screenOffsetX + (normalizedX * screenWidth),
                   y: screenOffsetY + (normalizedY * screenHeight))
}

func injectClick(at point: CGPoint) {
    let now = Date()
    guard now.timeIntervalSince(lastClickTime) > debounceInterval else { return }
    lastClickTime = now

    let timeSinceLastTouch = now.timeIntervalSince(lastTouchTime)
    let distanceFromLastTouch = hypot(point.x - lastTouchPoint.x, point.y - lastTouchPoint.y)
    let isDoubleClick = timeSinceLastTouch < doubleClickInterval && distanceFromLastTouch < doubleClickDistance

    lastTouchTime = now
    lastTouchPoint = point

    let originalPosition = NSEvent.mouseLocation
    let mainScreenHeight = NSScreen.screens[0].frame.height
    let originalCGPosition = CGPoint(x: originalPosition.x, y: mainScreenHeight - originalPosition.y)

    CGDisplayHideCursor(CGMainDisplayID())
    CGWarpMouseCursorPosition(point)
    usleep(10000)

    let clickCount: Int64 = isDoubleClick ? 2 : 1

    guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                   mouseCursorPosition: point, mouseButton: .left),
          let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                                 mouseCursorPosition: point, mouseButton: .left) else { return }

    mouseDown.setIntegerValueField(.mouseEventClickState, value: clickCount)
    mouseUp.setIntegerValueField(.mouseEventClickState, value: clickCount)

    mouseDown.post(tap: .cghidEventTap)
    usleep(20000)
    mouseUp.post(tap: .cghidEventTap)

    usleep(10000)
    CGWarpMouseCursorPosition(originalCGPosition)
    CGDisplayShowCursor(CGMainDisplayID())

    print(isDoubleClick ? "🖱️🖱️ ダブルクリック at (\(Int(point.x)), \(Int(point.y)))" : "🖱️  シングルクリック at (\(Int(point.x)), \(Int(point.y)))")
}

func injectDrag(to point: CGPoint) {
    guard let dragEvent = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: point, mouseButton: .left) else { return }
    CGWarpMouseCursorPosition(point)
    dragEvent.post(tap: .cghidEventTap)
}

func hidInputCallback(context: UnsafeMutableRawPointer?, result: IOReturn,
                      sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    updateScreenFromCurrentList()
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)

    if usagePage == 0x01 {
        switch usage {
        case 0x30: currentX = CGFloat(intValue)
        case 0x31: currentY = CGFloat(intValue)
        default: break
        }
    }

    let isTouchEvent = (usagePage == 0x0D && usage == 0x42) || (usagePage == 0x09 && usage == 0x01)
    if isTouchEvent {
        let wasTouching = isTouching
        isTouching = intValue != 0
        if isTouching && !wasTouching {
            injectClick(at: convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY)))
        } else if isTouching && wasTouching {
            injectDrag(to: convertToScreenCoordinates(rawX: Int(currentX), rawY: Int(currentY)))
        }
    }
}

func setupScreen() {
    let screens = NSScreen.screens
    print("📺 検出されたディスプレイ:")
    for (i, s) in screens.enumerated() {
        print("   [\(i)] \(s.localizedName): \(Int(s.frame.width))x\(Int(s.frame.height))")
    }
    if let s = screens.first(where: { $0.localizedName.contains("XENEON") || $0.localizedName.contains("Corsair") }) {
        targetScreen = s; print("✅ Xeneon Edge 検出!")
    } else if screens.count > 1 {
        targetScreen = screens[1]; print("⚠️  セカンダリディスプレイを使用")
    } else {
        targetScreen = NSScreen.main; print("⚠️  メインディスプレイを使用")
    }
    updateScreenGeometry()
}

var xeneonDisplayID: CGDirectDisplayID = 0

func findXeneonDisplayID() {
    var displayCount: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &displayCount)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    CGGetActiveDisplayList(displayCount, &displays, &displayCount)
    for d in displays { if d != CGMainDisplayID() { xeneonDisplayID = d; break } }
}

func updateScreenFromCurrentList() {
    guard xeneonDisplayID != 0 else { return }
    let b = CGDisplayBounds(xeneonDisplayID)
    screenOffsetX = b.origin.x; screenOffsetY = b.origin.y
    screenWidth = b.width; screenHeight = b.height
}

func updateScreenGeometry() {
    guard let screen = targetScreen else { return }
    let f = screen.frame
    let mainH = NSScreen.screens[0].frame.height
    screenOffsetX = f.origin.x
    screenOffsetY = mainH - f.origin.y - f.height
    screenWidth = f.width; screenHeight = f.height
    print("📐 ターゲット: \(Int(screenWidth))x\(Int(screenHeight)) @ (\(Int(screenOffsetX)), \(Int(screenOffsetY)))")
}

var lastKnownScreenOriginX: CGFloat = 0
var lastKnownScreenOriginY: CGFloat = 0
var lastKnownScreenWidth: CGFloat = 0
var lastKnownScreenHeight: CGFloat = 0

class ScreenChangeObserver {
    var timer: DispatchSourceTimer?
    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { _ in setupScreen(); saveCurrentGeometry() }
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer?.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer?.setEventHandler { checkForGeometryChanges() }
        timer?.resume()
    }
}

func saveCurrentGeometry() {
    if let s = targetScreen {
        lastKnownScreenOriginX = s.frame.origin.x; lastKnownScreenOriginY = s.frame.origin.y
        lastKnownScreenWidth = s.frame.width; lastKnownScreenHeight = s.frame.height
    }
}

func checkForGeometryChanges() {
    guard let x = NSScreen.screens.first(where: { $0.localizedName.contains("XENEON") || $0.localizedName.contains("Corsair") })
          ?? (NSScreen.screens.count > 1 ? NSScreen.screens[1] : nil) else { return }
    let f = x.frame
    if f.origin.x != lastKnownScreenOriginX || f.origin.y != lastKnownScreenOriginY ||
       f.width != lastKnownScreenWidth || f.height != lastKnownScreenHeight {
        targetScreen = x; updateScreenGeometry(); saveCurrentGeometry()
    }
}

var screenObserver: ScreenChangeObserver?

func checkAccessibilityPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func main() {
    print("""
    ╔════════════════════════════════════════════════════════════╗
    ║   Touchscreen Driver - Corsair Xeneon Edge      v1.4.0     ║
    ║   シングル＆ダブルクリック対応                              ║
    ╚════════════════════════════════════════════════════════════╝
    """)

    if !checkAccessibilityPermission() { print("⚠️  アクセシビリティ権限が必要です"); exit(1) }
    print("✅ アクセシビリティ権限OK")

    setupScreen(); findXeneonDisplayID(); saveCurrentGeometry()
    screenObserver = ScreenChangeObserver()

    print("""
    📊 設定:
       ダブルクリック: \(Int(doubleClickInterval * 1000))ms以内 / \(Int(doubleClickDistance))px以内
    """)

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let deviceMatch: [String: Any] = [kIOHIDVendorIDKey as String: TOUCHSCREEN_VENDOR_ID,
                                       kIOHIDProductIDKey as String: TOUCHSCREEN_PRODUCT_ID]
    IOHIDManagerSetDeviceMatching(manager, deviceMatch as CFDictionary)

    let openOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
    let openResult = IOHIDManagerOpen(manager, openOptions)
    guard openResult == kIOReturnSuccess else { print("❌ IOHIDManager起動失敗 (code: \(openResult))"); exit(1) }

    guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !deviceSet.isEmpty else {
        print("❌ タッチスクリーンが見つかりません"); exit(1)
    }
    print("✅ タッチスクリーン接続確認!")

    IOHIDManagerRegisterInputValueCallback(manager, hidInputCallback, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    print("""
    🎯 起動完了！
       シングルタップ → クリック
       素早く2回タップ → ダブルクリック
    """)

    CFRunLoopRun()
}

setbuf(stdout, nil)
main()
