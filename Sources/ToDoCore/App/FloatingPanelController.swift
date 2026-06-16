import AppKit
import Combine
import SwiftUI

@MainActor
public final class FloatingPanelController {
    private let store: TodoStore
    private let panel: FloatingTodoPanel
    private var settingsCancellable: AnyCancellable?
    private var rolloverTimer: Timer?

    public init(store: TodoStore) {
        self.store = store
        self.panel = FloatingTodoPanel()

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 520))
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor

        let rootView = FloatingTodoWidget(store: store) { [weak panel] in
            panel?.expandToComfortableSize()
        }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = containerView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 28
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let resizeView = ResizeHandleView(frame: containerView.bounds)
        resizeView.autoresizingMask = [.width, .height]

        containerView.addSubview(hostingView)
        containerView.addSubview(resizeView)

        panel.contentView = containerView
        panel.setFrame(NSRect(x: 120, y: 420, width: 330, height: 520), display: true)
        panel.centerIfNeeded()
        apply(settings: store.settings)

        settingsCancellable = store.$settings
            .sink { [weak self] settings in
                self?.apply(settings: settings)
            }

        // 应用长时间运行跨过午夜时，定期检查并滚动「今天/明天/后天」。
        let timer = Timer(timeInterval: 300, repeats: true) { _ in
            Task { @MainActor in store.rollOverIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }

    public func show() {
        store.rollOverIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    public func toggle() {
        panel.isVisible ? hide() : show()
    }

    private func apply(settings: TodoSettings) {
        panel.level = settings.alwaysOnTop ? .floating : .normal

        var behavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary]
        if settings.visibleOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }
        panel.collectionBehavior = behavior
        panel.allowsOptionClickInsideWidget = settings.effectiveOptionClickInsideWidget
        panel.ignoresMouseEvents = false
    }
}

private final class FloatingTodoPanel: NSPanel {
    var allowsOptionClickInsideWidget = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 520),
            styleMask: [.nonactivatingPanel, .borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        title = "Floating Todo"
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        hasShadow = false
        isOpaque = false
        sharingType = .readOnly
        minSize = NSSize(width: 220, height: 180)
        maxSize = NSSize(width: 440, height: 700)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        guard
            !allowsOptionClickInsideWidget,
            event.type == .leftMouseDown,
            event.modifierFlags.contains(.option)
        else {
            super.sendEvent(event)
            return
        }

        passOptionClickToLowerWindow(event)
    }

    /// 从紧凑模式一键恢复到舒适尺寸，保持窗口左上角不动，并夹在屏幕可见区域内。
    func expandToComfortableSize() {
        let target = NSSize(width: 330, height: 520)
        let width = min(max(target.width, minSize.width), maxSize.width)
        let height = min(max(target.height, minSize.height), maxSize.height)

        var newFrame = frame
        let topY = frame.maxY
        newFrame.size = NSSize(width: width, height: height)
        newFrame.origin.y = topY - height

        if let visible = NSScreen.main?.visibleFrame {
            newFrame.origin.x = min(newFrame.origin.x, visible.maxX - width)
            newFrame.origin.x = max(newFrame.origin.x, visible.minX)
            newFrame.origin.y = max(newFrame.origin.y, visible.minY)
            newFrame.origin.y = min(newFrame.origin.y, visible.maxY - height)
        }

        setFrame(newFrame, display: true, animate: true)
    }

    func centerIfNeeded() {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            center()
            return
        }

        let currentFrame = frame
        let origin = NSPoint(
            x: screenFrame.maxX - currentFrame.width - 36,
            y: screenFrame.maxY - currentFrame.height - 42
        )
        setFrameOrigin(origin)
    }

    private func passOptionClickToLowerWindow(_ event: NSEvent) {
        let screenPoint = convertPoint(toScreen: event.locationInWindow)
        let screenMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? screenPoint.y
        let eventPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        ignoresMouseEvents = true
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: eventPoint,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.ignoresMouseEvents = false
        }
    }
}

private final class ResizeHandleView: NSView {
    private struct ResizeEdges: OptionSet {
        let rawValue: Int

        static let left = ResizeEdges(rawValue: 1 << 0)
        static let right = ResizeEdges(rawValue: 1 << 1)
        static let top = ResizeEdges(rawValue: 1 << 2)
        static let bottom = ResizeEdges(rawValue: 1 << 3)
    }

    private let margin: CGFloat = 12

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        resizeEdges(at: point).isEmpty ? nil : self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: margin, width: margin, height: bounds.height - margin * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - margin, y: margin, width: margin, height: bounds.height - margin * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: margin, y: bounds.height - margin, width: bounds.width - margin * 2, height: margin), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: margin, y: 0, width: bounds.width - margin * 2, height: margin), cursor: .resizeUpDown)

        let cornerCursor = NSCursor.crosshair
        addCursorRect(NSRect(x: 0, y: 0, width: margin, height: margin), cursor: cornerCursor)
        addCursorRect(NSRect(x: bounds.width - margin, y: 0, width: margin, height: margin), cursor: cornerCursor)
        addCursorRect(NSRect(x: 0, y: bounds.height - margin, width: margin, height: margin), cursor: cornerCursor)
        addCursorRect(NSRect(x: bounds.width - margin, y: bounds.height - margin, width: margin, height: margin), cursor: cornerCursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let edges = resizeEdges(at: convert(event.locationInWindow, from: nil))
        guard !edges.isEmpty else { return }

        let startingFrame = window.frame
        let startingPoint = window.convertPoint(toScreen: event.locationInWindow)

        while true {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if nextEvent.type == .leftMouseUp { break }

            let currentPoint = window.convertPoint(toScreen: nextEvent.locationInWindow)
            let deltaX = currentPoint.x - startingPoint.x
            let deltaY = currentPoint.y - startingPoint.y

            var frame = startingFrame
            let minSize = window.minSize
            let maxSize = window.maxSize

            if edges.contains(.left) {
                let proposedWidth = startingFrame.width - deltaX
                frame.size.width = min(max(proposedWidth, minSize.width), maxSize.width)
                frame.origin.x = startingFrame.maxX - frame.size.width
            }
            if edges.contains(.right) {
                let proposedWidth = startingFrame.width + deltaX
                frame.size.width = min(max(proposedWidth, minSize.width), maxSize.width)
            }
            if edges.contains(.bottom) {
                let proposedHeight = startingFrame.height - deltaY
                frame.size.height = min(max(proposedHeight, minSize.height), maxSize.height)
                frame.origin.y = startingFrame.maxY - frame.size.height
            }
            if edges.contains(.top) {
                let proposedHeight = startingFrame.height + deltaY
                frame.size.height = min(max(proposedHeight, minSize.height), maxSize.height)
            }

            window.setFrame(frame, display: true)
        }
    }

    private func resizeEdges(at point: NSPoint) -> ResizeEdges {
        var edges: ResizeEdges = []
        if point.x <= margin { edges.insert(.left) }
        if point.x >= bounds.width - margin { edges.insert(.right) }
        if point.y <= margin { edges.insert(.bottom) }
        if point.y >= bounds.height - margin { edges.insert(.top) }
        return edges
    }
}
