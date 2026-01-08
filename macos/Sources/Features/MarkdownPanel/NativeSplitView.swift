import AppKit
import SwiftUI
import Combine

/// A native NSSplitView wrapper for SwiftUI that provides optimal drag performance.
/// Unlike pure SwiftUI approaches, NSSplitView handles resizing at the AppKit layer,
/// avoiding cascading SwiftUI re-renders during drag operations.
struct NativeSplitView<Left: View, Center: View, Right: View>: NSViewControllerRepresentable {
    // MARK: - Content Views
    let leftContent: Left
    let centerContent: Center
    let rightContent: Right

    // MARK: - Visibility State
    @Binding var leftVisible: Bool
    @Binding var rightVisible: Bool

    // MARK: - Width State (persisted)
    @Binding var leftWidth: CGFloat
    @Binding var rightWidth: CGFloat

    // MARK: - Constraints
    let leftMinWidth: CGFloat
    let leftMaxWidth: CGFloat
    let rightMinWidth: CGFloat
    let rightMaxWidthRatio: CGFloat  // As percentage of total width

    // MARK: - NSViewControllerRepresentable

    func makeNSViewController(context: Context) -> NativeSplitViewController {
        let controller = NativeSplitViewController()
        controller.delegate = context.coordinator

        // Set constraints
        controller.leftMinWidth = leftMinWidth
        controller.leftMaxWidth = leftMaxWidth
        controller.rightMinWidth = rightMinWidth
        controller.rightMaxWidthRatio = rightMaxWidthRatio

        // Initial widths
        controller.leftWidth = leftWidth
        controller.rightWidth = rightWidth

        // Set content views once (not in update to avoid infinite loop)
        controller.setLeftContent(NSHostingView(rootView: leftContent))
        controller.setCenterContent(NSHostingView(rootView: centerContent))
        controller.setRightContent(NSHostingView(rootView: rightContent))

        // Set initial visibility
        controller.setLeftVisible(leftVisible, animated: false)
        controller.setRightVisible(rightVisible, animated: false)

        return controller
    }

    func updateNSViewController(_ controller: NativeSplitViewController, context: Context) {
        // Update content in existing hosting views (don't recreate - that causes infinite loop)
        controller.updateLeftContent(leftContent)
        controller.updateCenterContent(centerContent)
        controller.updateRightContent(rightContent)

        // Update visibility
        controller.setLeftVisible(leftVisible, animated: true)
        controller.setRightVisible(rightVisible, animated: true)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NativeSplitViewControllerDelegate {
        var parent: NativeSplitView

        init(_ parent: NativeSplitView) {
            self.parent = parent
        }

        func splitViewDidResizeLeft(to width: CGFloat) {
            parent.leftWidth = width
        }

        func splitViewDidResizeRight(to width: CGFloat) {
            parent.rightWidth = width
        }
    }
}

// MARK: - Delegate Protocol

protocol NativeSplitViewControllerDelegate: AnyObject {
    func splitViewDidResizeLeft(to width: CGFloat)
    func splitViewDidResizeRight(to width: CGFloat)
}

// MARK: - NSSplitViewController Subclass

/// Custom split view controller that manages a 3-pane layout with collapsible sidebars.
/// Uses NSSplitView for native, performant drag resizing.
class NativeSplitViewController: NSViewController, NSSplitViewDelegate {

    // MARK: - Properties

    weak var delegate: NativeSplitViewControllerDelegate?

    /// The underlying split view
    private let splitView = NSSplitView()

    /// Container views for each pane
    private let leftContainer = NSView()
    private let centerContainer = NSView()
    private let rightContainer = NSView()

    /// Current content views
    private var leftContentView: NSView?
    private var centerContentView: NSView?
    private var rightContentView: NSView?

    /// Width constraints
    var leftMinWidth: CGFloat = 180
    var leftMaxWidth: CGFloat = 400
    var rightMinWidth: CGFloat = 280
    var rightMaxWidthRatio: CGFloat = 0.6

    /// Current widths (for restoration)
    var leftWidth: CGFloat = 240
    var rightWidth: CGFloat = 420

    /// Visibility state
    private var isLeftVisible = false
    private var isRightVisible = false

    /// Track if we're currently animating to prevent feedback loops
    private var isAnimating = false

    // MARK: - Lifecycle

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true  // Horizontal layout (left | center | right)
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autosaveName = "GhosttyPanelSplit"

        // Add to view hierarchy
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Setup containers (start with center only)
        setupContainers()
    }

    private func setupContainers() {
        // Configure containers
        for container in [leftContainer, centerContainer, rightContainer] {
            container.wantsLayer = true
        }

        // Add center container (always visible)
        splitView.addArrangedSubview(centerContainer)

        // Set holding priorities - center should be most flexible
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
    }

    // MARK: - Content Management

    func setLeftContent(_ view: NSView) {
        leftContentView?.removeFromSuperview()
        leftContentView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        leftContainer.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leftContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: leftContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: leftContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: leftContainer.bottomAnchor)
        ])
    }

    func setCenterContent(_ view: NSView) {
        centerContentView?.removeFromSuperview()
        centerContentView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        centerContainer.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: centerContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: centerContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: centerContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: centerContainer.bottomAnchor)
        ])
    }

    func setRightContent(_ view: NSView) {
        rightContentView?.removeFromSuperview()
        rightContentView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: rightContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rightContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: rightContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: rightContainer.bottomAnchor)
        ])
    }

    // MARK: - Content Updates (for SwiftUI state changes)

    func updateLeftContent<V: View>(_ content: V) {
        if let hostingView = leftContentView as? NSHostingView<V> {
            hostingView.rootView = content
        }
    }

    func updateCenterContent<V: View>(_ content: V) {
        if let hostingView = centerContentView as? NSHostingView<V> {
            hostingView.rootView = content
        }
    }

    func updateRightContent<V: View>(_ content: V) {
        if let hostingView = rightContentView as? NSHostingView<V> {
            hostingView.rootView = content
        }
    }

    // MARK: - Visibility Control

    func setLeftVisible(_ visible: Bool, animated: Bool) {
        guard visible != isLeftVisible else { return }
        isLeftVisible = visible

        if animated && !isAnimating {
            animatePanelVisibility(left: visible)
        } else {
            updateSplitViewArrangement()  // Apply immediately if animating or not animated
        }
    }

    func setRightVisible(_ visible: Bool, animated: Bool) {
        guard visible != isRightVisible else { return }
        isRightVisible = visible

        if animated && !isAnimating {
            animatePanelVisibility(right: visible)
        } else {
            updateSplitViewArrangement()  // Apply immediately if animating or not animated
        }
    }

    private func updateSplitViewArrangement() {
        // Remove all subviews
        for subview in splitView.arrangedSubviews {
            splitView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        // Add in order based on visibility
        var index = 0

        if isLeftVisible {
            splitView.insertArrangedSubview(leftContainer, at: index)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: index)
            index += 1
        }

        splitView.insertArrangedSubview(centerContainer, at: index)
        splitView.setHoldingPriority(.defaultLow, forSubviewAt: index)
        index += 1

        if isRightVisible {
            splitView.insertArrangedSubview(rightContainer, at: index)
            splitView.setHoldingPriority(.defaultHigh, forSubviewAt: index)
        }

        // Restore widths
        if isLeftVisible {
            leftContainer.frame.size.width = leftWidth
        }
        if isRightVisible {
            rightContainer.frame.size.width = rightWidth
        }

        splitView.adjustSubviews()
    }

    private func animatePanelVisibility(left: Bool? = nil, right: Bool? = nil) {
        guard !isAnimating else { return }
        isAnimating = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            updateSplitViewArrangement()

        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Determine which divider this is based on current arrangement
        if isLeftVisible && dividerIndex == 0 {
            // Left panel divider - enforce minimum left width
            return leftMinWidth
        } else if isLeftVisible && isRightVisible && dividerIndex == 1 {
            // Right panel divider - enforce center has some space
            return leftWidth + 100  // At least 100px for center
        } else if !isLeftVisible && isRightVisible && dividerIndex == 0 {
            // Only right panel visible - center needs minimum space
            return 100
        }

        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let totalWidth = splitView.bounds.width

        if isLeftVisible && dividerIndex == 0 {
            // Left panel divider - enforce maximum left width
            return min(leftMaxWidth, totalWidth * 0.4)
        } else if isRightVisible {
            // Right panel divider - enforce minimum right width
            return totalWidth - rightMinWidth
        }

        return proposedMaximumPosition
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        // Custom resize behavior: center takes all extra space
        splitView.adjustSubviews()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isAnimating else { return }

        // Report new widths to delegate
        if isLeftVisible, let leftIndex = splitView.arrangedSubviews.firstIndex(of: leftContainer) {
            let newLeftWidth = splitView.arrangedSubviews[leftIndex].frame.width
            if abs(newLeftWidth - leftWidth) > 1 {
                leftWidth = newLeftWidth
                delegate?.splitViewDidResizeLeft(to: newLeftWidth)
            }
        }

        if isRightVisible, let rightIndex = splitView.arrangedSubviews.firstIndex(of: rightContainer) {
            let newRightWidth = splitView.arrangedSubviews[rightIndex].frame.width
            if abs(newRightWidth - rightWidth) > 1 {
                rightWidth = newRightWidth
                delegate?.splitViewDidResizeRight(to: newRightWidth)
            }
        }
    }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // Never hide dividers when panels are visible
        return false
    }

    // Custom divider appearance
    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        // Expand the effective (clickable) rect while keeping visual rect thin
        var effectiveRect = proposedEffectiveRect
        effectiveRect.origin.x -= 4
        effectiveRect.size.width += 8
        return effectiveRect
    }
}

// MARK: - Convenience Initializer

extension NativeSplitView {
    /// Creates a native split view with default constraints
    init(
        leftVisible: Binding<Bool>,
        rightVisible: Binding<Bool>,
        leftWidth: Binding<CGFloat>,
        rightWidth: Binding<CGFloat>,
        @ViewBuilder left: () -> Left,
        @ViewBuilder center: () -> Center,
        @ViewBuilder right: () -> Right
    ) {
        self.leftContent = left()
        self.centerContent = center()
        self.rightContent = right()
        self._leftVisible = leftVisible
        self._rightVisible = rightVisible
        self._leftWidth = leftWidth
        self._rightWidth = rightWidth
        self.leftMinWidth = 180
        self.leftMaxWidth = 400
        self.rightMinWidth = 280
        self.rightMaxWidthRatio = 0.6
    }
}
