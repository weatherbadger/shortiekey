import AppKit

class WindowManager {

    // Stores the pre-fullscreen frame per window (keyed by AX window description)
    private var savedFrames: [String: CGRect] = [:]

    // MARK: - Helpers

    func getFrontmostWindow(for app: NSRunningApplication?) -> AXUIElement? {
        let targetApp = app ?? NSWorkspace.shared.frontmostApplication
        guard let targetApp = targetApp else { return nil }
        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue)
        guard result == .success, let window = windowValue else { return nil }
        return (window as! AXUIElement)
    }

    func getScreen(for window: AXUIElement) -> NSScreen? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard let posVal = positionValue,
              AXValueGetValue(posVal as! AXValue, AXValueType.cgPoint, &position),
              let sizeVal = sizeValue,
              AXValueGetValue(sizeVal as! AXValue, AXValueType.cgSize, &size)
        else { return nil }

        // AX position is in top-left origin coords; convert midpoint for screen hit-test
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let midX = position.x + size.width / 2
        // Convert AX Y (top-left) to NSScreen Y (bottom-left)
        let midY = primaryHeight - position.y - size.height / 2

        for screen in NSScreen.screens {
            if screen.frame.contains(CGPoint(x: midX, y: midY)) {
                return screen
            }
        }
        return NSScreen.main
    }

    func setFrame(_ frame: CGRect, for window: AXUIElement) {
        // NSScreen uses bottom-left origin (Y increases upward).
        // AXUIElement uses top-left origin of the primary screen (Y increases downward).
        // Convert: axY = primaryScreenHeight - nsY - windowHeight
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        var origin = CGPoint(
            x: frame.origin.x,
            y: primaryScreenHeight - frame.origin.y - frame.height
        )
        var size = frame.size

        if let posValue = AXValueCreate(AXValueType.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(AXValueType.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    // MARK: - Snap Actions

    func snapLeft(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screen = getScreen(for: window) ?? NSScreen.main!
        let vf = screen.visibleFrame
        setFrame(CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height), for: window)
    }

    func snapRight(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screen = getScreen(for: window) ?? NSScreen.main!
        let vf = screen.visibleFrame
        setFrame(CGRect(x: vf.midX, y: vf.minY, width: vf.width / 2, height: vf.height), for: window)
    }

    func snapTop(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screen = getScreen(for: window) ?? NSScreen.main!
        let vf = screen.visibleFrame
        setFrame(CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: vf.height / 2), for: window)
    }

    func snapBottom(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screen = getScreen(for: window) ?? NSScreen.main!
        let vf = screen.visibleFrame
        setFrame(CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2), for: window)
    }

    func snapFullscreen(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screen = getScreen(for: window) ?? NSScreen.main!
        let vf = screen.visibleFrame
        // Save the current frame before going fullscreen so restoreWindow can undo it
        if let currentFrame = getFrameNS(for: window) {
            savedFrames[windowKey(window)] = currentFrame
        }
        setFrame(CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height), for: window)
    }

    func restoreWindow(for app: NSRunningApplication? = nil) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let key = windowKey(window)
        guard let savedFrame = savedFrames[key] else { return }
        setFrame(savedFrame, for: window)
        savedFrames.removeValue(forKey: key)
    }

    // Returns a stable string key for a window element
    private func windowKey(_ window: AXUIElement) -> String {
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
        let title = (titleValue as? String) ?? "unknown"
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return "\(pid)-\(title)"
    }

    // Returns the current window frame in NSScreen coordinates
    private func getFrameNS(for window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }
        var axPos = CGPoint.zero
        var size = CGSize.zero
        guard let posVal = positionValue,
              AXValueGetValue(posVal as! AXValue, .cgPoint, &axPos),
              let sizeVal = sizeValue,
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsY = primaryHeight - axPos.y - size.height
        return CGRect(x: axPos.x, y: nsY, width: size.width, height: size.height)
    }

    // MARK: - Move Between Screens

    func moveToNextScreen(for app: NSRunningApplication? = nil) {
        moveToScreen(offset: 1, for: app)
    }

    func moveToPreviousScreen(for app: NSRunningApplication? = nil) {
        moveToScreen(offset: -1, for: app)
    }

    private func moveToScreen(offset: Int, for app: NSRunningApplication?) {
        guard let window = getFrontmostWindow(for: app) else { return }
        let screens = NSScreen.screens
        guard screens.count > 1 else { return }

        let currentScreen = getScreen(for: window) ?? NSScreen.main!
        guard let currentIndex = screens.firstIndex(of: currentScreen) else { return }

        let targetIndex = (currentIndex + offset + screens.count) % screens.count
        let targetScreen = screens[targetIndex]

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return }

        var axPosition = CGPoint.zero
        var size = CGSize.zero

        guard let posVal = positionValue,
              AXValueGetValue(posVal as! AXValue, AXValueType.cgPoint, &axPosition),
              let sizeVal = sizeValue,
              AXValueGetValue(sizeVal as! AXValue, AXValueType.cgSize, &size)
        else { return }

        // Convert AX position to NSScreen coordinates for ratio calculation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let nsPosition = CGPoint(
            x: axPosition.x,
            y: primaryHeight - axPosition.y - size.height
        )

        let currentVF = currentScreen.visibleFrame
        let targetVF = targetScreen.visibleFrame

        let xRatio = (nsPosition.x - currentVF.minX) / currentVF.width
        let yRatio = (nsPosition.y - currentVF.minY) / currentVF.height
        let widthRatio = size.width / currentVF.width
        let heightRatio = size.height / currentVF.height

        let targetFrame = CGRect(
            x: targetVF.minX + xRatio * targetVF.width,
            y: targetVF.minY + yRatio * targetVF.height,
            width: widthRatio * targetVF.width,
            height: heightRatio * targetVF.height
        )

        setFrame(targetFrame, for: window)
    }
}
