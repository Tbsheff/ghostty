import AppKit
import SwiftUI
import Combine
import QuartzCore

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

    /// Track if we're currently dragging dividers to show preview overlay
    private var isDraggingDivider = false

    /// Divider preview overlay view
    private let dividerPreviewOverlay = NSView()
    
    /// Minimum width for center pane to remain functional
    private let minCenterWidth: CGFloat = 150
    
    /// User preference state (whether panels were explicitly hidden by user)
    private var userPreferredLeftVisible = true
    private var userPreferredRightVisible = true

    /// Track auto-collapse so we can restore when width allows
    private var autoCollapsedLeft = false
    private var autoCollapsedRight = false

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

        // Setup divider preview overlay (semi-transparent overlay shown during resize)
        setupDividerPreviewOverlay()

        // Setup containers (start with center only)
        setupContainers()
    }

    private func setupDividerPreviewOverlay() {
        dividerPreviewOverlay.wantsLayer = true
        dividerPreviewOverlay.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        dividerPreviewOverlay.isHidden = true
        view.addSubview(dividerPreviewOverlay)
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
        userPreferredLeftVisible = visible  // Track user preference
        autoCollapsedLeft = false

        if animated && !isAnimating {
            animatePanelVisibility(left: visible)
        } else {
            updateSplitViewArrangement()  // Apply immediately if animating or not animated
        }
    }

    func setRightVisible(_ visible: Bool, animated: Bool) {
        guard visible != isRightVisible else { return }
        isRightVisible = visible
        userPreferredRightVisible = visible  // Track user preference
        autoCollapsedRight = false

        if animated && !isAnimating {
            animatePanelVisibility(right: visible)
        } else {
            updateSplitViewArrangement()  // Apply immediately if animating or not animated
        }
    }

    // MARK: - Adaptive Panel Sizing

    /// Calculate dynamic breakpoint for left sidebar based on user-preferred width
    /// Collapses when: totalWidth < (leftWidth + minCenterWidth + rightWidth if rightVisible)
    private func calculateLeftBreakpoint() -> CGFloat {
        var requiredWidth = leftWidth + minCenterWidth
        if isRightVisible {
            requiredWidth += rightWidth
        }
        return requiredWidth
    }
    
    /// Calculate dynamic breakpoint for right sidebar based on user-preferred width
    /// Collapses when: totalWidth < (leftWidth if leftVisible + centerWidth + rightWidth)
    private func calculateRightBreakpoint() -> CGFloat {
        var requiredWidth = rightWidth + minCenterWidth
        if isLeftVisible {
            requiredWidth += leftWidth
        }
        return requiredWidth
    }

    /// Check if current window size requires auto-collapse based on dynamic breakpoints
    /// Breakpoints are calculated from user-preferred widths, ensuring responsive behavior
    /// Preserves user preference when width returns to adequate range
    private func checkAndAutoCollapse() {
        let totalWidth = splitView.bounds.width
        
        // Calculate dynamic breakpoints based on current preferred widths
        let leftBreakpoint = calculateLeftBreakpoint()
        let rightBreakpoint = calculateRightBreakpoint()
        
        // Determine auto-collapse state based on dynamic breakpoints
        let shouldCollapseRight = totalWidth < rightBreakpoint
        let shouldCollapseLeft = totalWidth < leftBreakpoint
        
        var needsUpdate = false
        
        // Handle right sidebar auto-collapse
        if shouldCollapseRight && isRightVisible {
            autoCollapsedRight = true
            isRightVisible = false
            needsUpdate = true
        } else if !shouldCollapseRight && autoCollapsedRight {
            // Restore right sidebar if width is sufficient and user prefers it visible
            isRightVisible = userPreferredRightVisible
            autoCollapsedRight = false
            needsUpdate = true
        }
        
        // Handle left sidebar auto-collapse
        if shouldCollapseLeft && isLeftVisible {
            autoCollapsedLeft = true
            isLeftVisible = false
            needsUpdate = true
        } else if !shouldCollapseLeft && autoCollapsedLeft {
            // Restore left sidebar if width is sufficient and user prefers it visible
            isLeftVisible = userPreferredLeftVisible
            autoCollapsedLeft = false
            needsUpdate = true
        }
        
        if needsUpdate {
            updateSplitViewArrangement()
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
    
    /// Animate panel visibility changes with smooth transitions
    private func updateSplitViewArrangementWithAnimation() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { [weak self] in
            self?.splitView.needsLayout = true
        }
        
        updateSplitViewArrangement()
        
        CATransaction.commit()
    }

    private func animatePanelVisibility(left: Bool? = nil, right: Bool? = nil) {
        guard !isAnimating else { return }
        isAnimating = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            updateSplitViewArrangementWithAnimation()

        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    // MARK: - Divider Preview Overlay

    private func showDividerPreview(at position: CGFloat, forDividerAt dividerIndex: Int) {
        isDraggingDivider = true
        dividerPreviewOverlay.isHidden = false

        // Set frame for the divider preview (thin vertical line)
        let dividerWidth: CGFloat = 4
        dividerPreviewOverlay.frame = NSRect(
            x: position - dividerWidth / 2,
            y: 0,
            width: dividerWidth,
            height: splitView.bounds.height
        )
    }

    private func hideDividerPreview() {
        isDraggingDivider = false
        dividerPreviewOverlay.isHidden = true
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        // Show divider preview during dragging
        showDividerPreview(at: proposedMinimumPosition, forDividerAt: dividerIndex)

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
        // Show divider preview during dragging
        showDividerPreview(at: proposedMaximumPosition, forDividerAt: dividerIndex)

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
        // Check for adaptive collapse before resizing
        checkAndAutoCollapse()
        
        // Custom resize behavior: center takes all extra space
        splitView.adjustSubviews()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard !isAnimating else { return }

        // Hide divider preview after resize completes
        if isDraggingDivider {
            // Use a small delay to allow the final resize to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.hideDividerPreview()
            }
        }

        // Check for adaptive collapse after resize
        checkAndAutoCollapse()

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
