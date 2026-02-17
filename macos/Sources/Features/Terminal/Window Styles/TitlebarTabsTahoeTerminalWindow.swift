import AppKit
import SwiftUI

/// `macos-titlebar-style = tabs` for macOS 26 (Tahoe) and later.
///
/// This inherits from transparent styling so that the titlebar matches the background color
/// of the window.
class TitlebarTabsTahoeTerminalWindow: TransparentTitlebarTerminalWindow, NSToolbarDelegate {
    /// The view model for SwiftUI views
    private var viewModel = ViewModel()

    /// Left sidebar toggle button
    private lazy var fileBrowserButton: NSHostingView<ToolbarToggleButton> = {
        let view = NSHostingView(rootView: ToolbarToggleButton(
            viewModel: viewModel,
            icon: "sidebar.left",
            isActiveKeyPath: \.fileBrowserVisible,
            accessibilityIdentifier: "fileBrowser.toggle",
            action: { [weak self] in
                self?.terminalController?.toggleFileBrowser(nil)
            }
        ))
        view.setAccessibilityIdentifier("fileBrowser.toggle")
        view.setAccessibilityRole(.button)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Right markdown toggle button
    private lazy var markdownButton: NSHostingView<ToolbarToggleButton> = {
        let view = NSHostingView(rootView: ToolbarToggleButton(
            viewModel: viewModel,
            icon: "doc.richtext",
            isActiveKeyPath: \.markdownVisible,
            accessibilityIdentifier: "markdown.toggle",
            action: { [weak self] in
                self?.terminalController?.toggleMarkdownPreview(nil)
            }
        ))
        view.setAccessibilityIdentifier("markdown.toggle")
        view.setAccessibilityRole(.button)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Custom SwiftUI tab bar that replaces the native NSTabBar
    private lazy var customTabBarHostingView: NSHostingView<CustomTabBarView> = {
        let view = NSHostingView(rootView: CustomTabBarView(
            viewModel: viewModel,
            onSelectTab: { [weak self] window in
                window.makeKeyAndOrderFront(nil)
            },
            onCloseTab: { [weak self] window in
                guard let controller = window.windowController as? TerminalController else { return }
                controller.closeTab(nil)
            },
            onNewTab: { [weak self] in
                self?.terminalController?.newTab(self)
            }
        ))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Titlebar tabs can't support the update accessory because of the way we layout
    /// the native tabs back into the menu bar.
    override var supportsUpdateAccessory: Bool { false }

    deinit {
        tabBarObserver = nil
    }

    // MARK: NSWindow

    override var titlebarFont: NSFont? {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewModel.titleFont = self.titlebarFont
            }
        }
    }

    override var title: String {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewModel.title = self.title
                self.refreshTabs()
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        // We must hide the title since we're going to be moving tabs into
        // the titlebar which have their own title.
        titleVisibility = .hidden

        // Create a toolbar
        let toolbar = NSToolbar(identifier: "TerminalToolbar")
        toolbar.delegate = self
        toolbar.centeredItemIdentifiers.insert(.title)
        self.toolbar = toolbar
        toolbarStyle = .unifiedCompact
    }

    override func becomeMain() {
        super.becomeMain()

        // Check if we have a tab bar and set it up if we have to. See the comment
        // on this function to learn why we need to check this here.
        setupTabBar()
        refreshTabs()

        viewModel.isMainWindow = true
    }

    override func resignMain() {
        super.resignMain()

        viewModel.isMainWindow = false
    }

    override func updatePanelState(fileBrowserVisible: Bool, markdownVisible: Bool) {
        super.updatePanelState(fileBrowserVisible: fileBrowserVisible, markdownVisible: markdownVisible)
        self.viewModel.fileBrowserVisible = fileBrowserVisible
        self.viewModel.markdownVisible = markdownVisible
    }

    /// On our Tahoe titlebar tabs, we need to fix up right click events because they don't work
    /// naturally due to whatever mess we made.
    override func sendEvent(_ event: NSEvent) {
        guard viewModel.hasTabBar else {
            super.sendEvent(event)
            return
        }

        let isRightClick =
            event.type == .rightMouseDown ||
            (event.type == .otherMouseDown && event.buttonNumber == 2) ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        guard isRightClick else {
            super.sendEvent(event)
            return
        }
        
        guard let tabBarView else {
            super.sendEvent(event)
            return
        }
        
        let locationInTabBar = tabBarView.convert(event.locationInWindow, from: nil)
        guard tabBarView.bounds.contains(locationInTabBar) else {
            super.sendEvent(event)
            return
        }
        
        tabBarView.rightMouseDown(with: event)
    }

    // This is called by macOS for native tabbing in order to add the tab bar. We hook into
    // this, detect the tab bar being added, and override its behavior.
    override func addTitlebarAccessoryViewController(_ childViewController: NSTitlebarAccessoryViewController) {
        // If this is the tab bar then we need to set it up for the titlebar
        guard isTabBar(childViewController) else {
            // After dragging a tab into a new window, `hasTabBar` needs to be
            // updated to properly review window title
            viewModel.hasTabBar = false
            
            super.addTitlebarAccessoryViewController(childViewController)
            return
        }

        // When an existing tab is being dragged in to another tab group,
        // system will also try to add tab bar to this window, so we want to reset observer,
        // to put tab bar where we want again
        tabBarObserver = nil
        
        // Some setup needs to happen BEFORE it is added, such as layout. If
        // we don't do this before the call below, we'll trigger an AppKit
        // assertion.
        childViewController.layoutAttribute = .right

        super.addTitlebarAccessoryViewController(childViewController)

        // Setup the tab bar to go into the titlebar.
        DispatchQueue.main.async {
            // HACK: wait a tick before doing anything, to avoid edge cases during startup... :/
            // If we don't do this then on launch windows with restored state with tabs will end
            // up with messed up tab bars that don't show all tabs.
            self.setupTabBar()
        }
    }

    override func removeTitlebarAccessoryViewController(at index: Int) {
        guard let childViewController = titlebarAccessoryViewControllers[safe: index],
                isTabBar(childViewController) else {
            super.removeTitlebarAccessoryViewController(at: index)
            return
        }

        super.removeTitlebarAccessoryViewController(at: index)

        removeTabBar()
    }

    // MARK: Tab Bar Setup

    private var tabBarObserver: NSObjectProtocol? {
        didSet {
            // When we change this we want to clear our old observer
            guard let oldValue else { return }
            NotificationCenter.default.removeObserver(oldValue)
        }
    }

    /// Take the NSTabBar that is on the window and convert it into titlebar tabs.
    ///
    /// Let me explain more background on what is happening here. When a tab bar is created, only the
    /// main window actually has an NSTabBar. When an NSWindow in the tab group gains main, AppKit
    /// creates/moves (unsure which) the NSTabBar for it and shows it. When it loses main, the tab bar
    /// is removed from the view hierarchy.
    ///
    /// We can't reliably detect this via `addTitlebarAccessoryViewController` because AppKit
    /// creates an accessory view controller for every window in the tab group, but only attaches
    /// the actual NSTabBar to the main window's accessory view.
    ///
    /// The best way I've found to detect this is to search for and setup the tab bar anytime the
    /// window gains focus. There are probably edge cases to check but to resolve all this I made
    /// this function which is idempotent to call.
    ///
    /// There are more scenarios to look out for and they're documented within the method.
    func setupTabBar() {
        // We only want to setup the observer once
        guard tabBarObserver == nil else { return }

        guard
            let titlebarView,
            let tabBarView = self.tabBarView
        else { return }

        // View model updates must happen on their own ticks.
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.hasTabBar = true
        }

        // Find our clip view
        guard let clipView = tabBarView.firstSuperview(withClassName: "NSTitlebarAccessoryClipView") else { return }
        guard let toolbarView = titlebarView.firstDescendant(withClassName: "NSToolbarView") else { return }

        // Hide the native tab bar visually but keep it in the hierarchy
        // so macOS tab group internals (drag-to-new-window, etc.) still work.
        tabBarView.alphaValue = 0
        tabBarView.frame.size.height = 0

        // The container is the view that we'll constrain our tab bar within.
        let container = toolbarView

        // The padding for the tab bar. If we're showing window buttons then
        // we need to offset the window buttons.
        let leftPadding: CGFloat = switch(self.derivedConfig.macosWindowButtons) {
        case .hidden: 0
        case .visible: 70
        }

        // Add toggle buttons to the toolbar view
        let buttonWidth: CGFloat = 32
        let buttonPadding: CGFloat = 8

        // Add custom tab bar view first (lowest in subview stack for hit testing)
        if customTabBarHostingView.superview != container {
            customTabBarHostingView.removeFromSuperview()
            container.addSubview(customTabBarHostingView)
        }

        // Add toggle buttons AFTER tab bar so they're frontmost for hit testing.
        // AppKit routes mouse events by subview order (last = frontmost), not zPosition.
        if fileBrowserButton.superview != container {
            fileBrowserButton.removeFromSuperview()
            container.addSubview(fileBrowserButton)
        }

        if markdownButton.superview != container {
            markdownButton.removeFromSuperview()
            container.addSubview(markdownButton)
        }

        // Hide the native clip view (keep it but zero-sized so macOS internals work)
        clipView.translatesAutoresizingMaskIntoConstraints = false

        // Setup all our constraints - leave room for toggle buttons on left and right
        let tabBarLeftPadding = leftPadding + buttonWidth + buttonPadding
        let tabBarRightPadding = buttonWidth + buttonPadding

        NSLayoutConstraint.activate([
            // File browser button constraints (left side)
            fileBrowserButton.leftAnchor.constraint(equalTo: container.leftAnchor, constant: leftPadding + buttonPadding),
            fileBrowserButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fileBrowserButton.widthAnchor.constraint(equalToConstant: 28),
            fileBrowserButton.heightAnchor.constraint(equalToConstant: 22),

            // Markdown button constraints (right side)
            markdownButton.rightAnchor.constraint(equalTo: container.rightAnchor, constant: -buttonPadding),
            markdownButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            markdownButton.widthAnchor.constraint(equalToConstant: 28),
            markdownButton.heightAnchor.constraint(equalToConstant: 22),

            // Custom tab bar constraints (between the buttons)
            customTabBarHostingView.leftAnchor.constraint(equalTo: container.leftAnchor, constant: tabBarLeftPadding),
            customTabBarHostingView.rightAnchor.constraint(equalTo: container.rightAnchor, constant: -tabBarRightPadding),
            customTabBarHostingView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            customTabBarHostingView.heightAnchor.constraint(equalTo: container.heightAnchor),

            // Zero-size the native clip view
            clipView.widthAnchor.constraint(equalToConstant: 0),
            clipView.heightAnchor.constraint(equalToConstant: 0),
        ])

        // Refresh tab state
        refreshTabs()

        // Setup an observer for the NSTabBar frame. When system appearance changes or
        // other events occur, the tab bar can resize and clear our constraints. When this
        // happens, we need to remove our custom constraints and re-apply them once the
        // tab bar has proper dimensions again to avoid constraint conflicts.
        tabBarView.postsFrameChangedNotifications = true
        tabBarObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: tabBarView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            // Remove the observer so we can call setup again.
            self.tabBarObserver = nil

            // Wait a tick to let the new tab bars appear and then set them up.
            DispatchQueue.main.async {
                self.setupTabBar()
                self.refreshTabs()
            }
        }
    }

    /// Reads the current tab group state and updates the view model's tab list.
    private func refreshTabs() {
        guard let windows = tabbedWindows as? [TerminalWindow] else {
            viewModel.tabs = []
            return
        }

        viewModel.tabs = windows.enumerated().map { index, window in
            let controller = window.terminalController
            let hasRunning = controller?.surfaceTree.contains(where: { $0.needsConfirmQuit }) ?? false
            let hasBell = controller?.focusedSurface?.bell ?? false
            return ViewModel.TabInfo(
                id: ObjectIdentifier(window),
                title: window.title,
                isSelected: window === self,
                tabColor: window.tabColor,
                keyEquivalent: window.keyEquivalent,
                hasRunningProcess: hasRunning,
                hasBell: hasBell,
                window: window
            )
        }
    }

    func removeTabBar() {
        // View model needs to be updated on another tick because it
        // triggers view updates.
        DispatchQueue.main.async {
            self.viewModel.hasTabBar = false
            self.viewModel.tabs = []
        }

        // Remove toggle buttons and custom tab bar from the toolbar
        fileBrowserButton.removeFromSuperview()
        markdownButton.removeFromSuperview()
        customTabBarHostingView.removeFromSuperview()

        // Clear our observations
        self.tabBarObserver = nil
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.title, .flexibleSpace, .space]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, .title, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .title:
            let item = NSToolbarItem(itemIdentifier: .title)
            item.view = NSHostingView(rootView: TitleItem(viewModel: viewModel))
            // Fix: https://github.com/ghostty-org/ghostty/discussions/9027
            item.view?.setContentCompressionResistancePriority(.required, for: .horizontal)
            item.visibilityPriority = .user
            item.isEnabled = true

            // This is the documented way to avoid the glass view on an item.
            // We don't want glass on our title.
            item.isBordered = false

            return item
        case .fileBrowserToggle:
            let item = NSToolbarItem(itemIdentifier: .fileBrowserToggle)
            let hostingView = NSHostingView(rootView: ToolbarToggleButton(
                icon: "sidebar.left",
                isActive: viewModel.fileBrowserVisible,
                accessibilityIdentifier: "fileBrowser.toggle",
                action: { [weak self] in
                    self?.terminalController?.toggleFileBrowser(nil)
                }
            ))
            hostingView.frame = NSRect(x: 0, y: 0, width: 28, height: 22)
            hostingView.setAccessibilityIdentifier("fileBrowser.toggle")
            hostingView.setAccessibilityRole(.button)
            item.view = hostingView
            item.view?.setAccessibilityIdentifier("fileBrowser.toggle")
            item.view?.setAccessibilityRole(.button)
            item.isBordered = false
            item.visibilityPriority = .high
            item.toolTip = "Toggle File Browser (⌘B)"
            item.minSize = NSSize(width: 28, height: 22)
            item.maxSize = NSSize(width: 28, height: 22)
            return item
        case .markdownToggle:
            let item = NSToolbarItem(itemIdentifier: .markdownToggle)
            let hostingView = NSHostingView(rootView: ToolbarToggleButton(
                icon: "doc.richtext",
                isActive: viewModel.markdownVisible,
                accessibilityIdentifier: "markdown.toggle",
                action: { [weak self] in
                    self?.terminalController?.toggleMarkdownPreview(nil)
                }
            ))
            hostingView.frame = NSRect(x: 0, y: 0, width: 28, height: 22)
            hostingView.setAccessibilityIdentifier("markdown.toggle")
            hostingView.setAccessibilityRole(.button)
            item.view = hostingView
            item.view?.setAccessibilityIdentifier("markdown.toggle")
            item.view?.setAccessibilityRole(.button)
            item.isBordered = false
            item.visibilityPriority = .high
            item.toolTip = "Toggle Panel (⇧⌘M)"
            item.minSize = NSSize(width: 28, height: 22)
            item.maxSize = NSSize(width: 28, height: 22)
            return item
        default:
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }
    }

    // MARK: SwiftUI

    class ViewModel: ObservableObject {
        @Published var titleFont: NSFont?
        @Published var title: String = "👻 Ghostty"
        @Published var hasTabBar: Bool = false
        @Published var isMainWindow: Bool = true
        @Published var fileBrowserVisible: Bool = false
        @Published var markdownVisible: Bool = false

        // Tab state for custom tab bar
        @Published var tabs: [TabInfo] = []

        struct TabInfo: Identifiable {
            let id: ObjectIdentifier
            let title: String
            let isSelected: Bool
            let tabColor: TerminalTabColor
            let keyEquivalent: String?
            let hasRunningProcess: Bool
            let hasBell: Bool
            weak var window: NSWindow?
        }
    }
}

extension NSToolbarItem.Identifier {
    /// Displays the title of the window
    static let title = NSToolbarItem.Identifier("Title")
    /// Toggle file browser panel
    static let fileBrowserToggle = NSToolbarItem.Identifier("FileBrowserToggle")
    /// Toggle markdown preview panel
    static let markdownToggle = NSToolbarItem.Identifier("MarkdownToggle")
}

extension TitlebarTabsTahoeTerminalWindow {
    /// Displays the window title
    struct TitleItem: View {
        @ObservedObject var viewModel: ViewModel

        var title: String {
            // An empty title makes this view zero-sized and NSToolbar on macOS
            // tahoe just deletes the item when that happens. So we use a space
            // instead to ensure there's always some size.
            return viewModel.title.isEmpty ? " " : viewModel.title
        }

        var body: some View {
            if !viewModel.hasTabBar {
                titleText
            } else {
                // 1x1.gif strikes again! For real: if we render a zero-sized
                // view here then the toolbar just disappears our view. I don't
                // know. On macOS 26.1+ the view no longer disappears, but the
                // toolbar still logs an ambiguous content size warning.
                Color.clear.frame(width: 1, height: 1)
            }
        }
        
        @ViewBuilder
        var titleText: some View {
            Text(title)
                .font(viewModel.titleFont.flatMap(Font.init(_:)))
                .foregroundStyle(viewModel.isMainWindow ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .greatestFiniteMagnitude, alignment: .center)
                .opacity(viewModel.hasTabBar ? 0 : 1) // hide when in fullscreen mode, where title bar will appear in the leading area under window buttons
        }
    }

    /// A toggle button for the toolbar - supports both static and reactive modes
    struct ToolbarToggleButton: View {
        // For reactive mode with viewModel
        @ObservedObject private var viewModel: ViewModel
        private let isActiveKeyPath: KeyPath<ViewModel, Bool>?

        // For static mode
        private let staticIsActive: Bool?

        let icon: String
        let accessibilityIdentifier: String?
        let action: () -> Void

        @State private var isHovered = false

        /// Reactive initializer - updates when viewModel changes
        init(viewModel: ViewModel, icon: String, isActiveKeyPath: KeyPath<ViewModel, Bool>, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
            self.viewModel = viewModel
            self.icon = icon
            self.isActiveKeyPath = isActiveKeyPath
            self.staticIsActive = nil
            self.accessibilityIdentifier = accessibilityIdentifier
            self.action = action
        }

        /// Static initializer - for toolbar items that don't need reactive updates
        init(icon: String, isActive: Bool, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
            self.viewModel = ViewModel()
            self.icon = icon
            self.isActiveKeyPath = nil
            self.staticIsActive = isActive
            self.accessibilityIdentifier = accessibilityIdentifier
            self.action = action
        }

        private var isActive: Bool {
            if let keyPath = isActiveKeyPath {
                return viewModel[keyPath: keyPath]
            }
            return staticIsActive ?? false
        }

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(buttonColor)
            }
            .buttonStyle(.plain)
            .modifier(AccessibilityIdentifierModifier(identifier: accessibilityIdentifier))
            .frame(width: 28, height: 22)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusMedium))
            .onHover { isHovered = $0 }
        }

        private var buttonColor: Color {
            if isActive {
                return .accentColor
            }
            return isHovered ? .primary : .secondary
        }

        private var backgroundColor: Color {
            if isActive {
                return Color.accentColor.opacity(0.2)
            }
            return isHovered ? Color.primary.opacity(0.1) : .clear
        }
    }

    // MARK: - Custom Tab Bar

    /// A fully custom tab bar that replaces the native NSTabBar.
    struct CustomTabBarView: View {
        @ObservedObject var viewModel: ViewModel
        let onSelectTab: (NSWindow) -> Void
        let onCloseTab: (NSWindow) -> Void
        let onNewTab: () -> Void

        var body: some View {
            HStack(spacing: 2) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(viewModel.tabs) { tab in
                            CustomTabItem(
                                tab: tab,
                                onSelect: { if let w = tab.window { onSelectTab(w) } },
                                onClose: { if let w = tab.window { onCloseTab(w) } }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .padding(.trailing, AdaptiveTheme.spacing4)
            }
        }
    }

    /// Individual tab pill with hover/select states, close button, and color indicator.
    struct CustomTabItem: View {
        let tab: ViewModel.TabInfo
        let onSelect: () -> Void
        let onClose: () -> Void

        @State private var isHovered = false
        @State private var pulseOpacity: Double = 0.4

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: AdaptiveTheme.spacing4) {
                    if tab.tabColor != .none, let displayColor = tab.tabColor.displayColor {
                        Circle()
                            .fill(Color(nsColor: displayColor))
                            .frame(width: 7, height: 7)
                    }

                    if !tab.isSelected && tab.hasBell {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 5, height: 5)
                    } else if !tab.isSelected && tab.hasRunningProcess {
                        Circle()
                            .fill(Color.accentColor.opacity(pulseOpacity))
                            .frame(width: 5, height: 5)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                    pulseOpacity = 1.0
                                }
                            }
                    }

                    Text(tab.title)
                        .font(.system(size: 11.5, weight: tab.isSelected ? .medium : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(tab.isSelected ? .primary : .secondary)

                    CloseTabButton(action: onClose)
                        .opacity(isHovered ? 1 : 0)
                }
                .padding(.horizontal, AdaptiveTheme.spacing8)
                .padding(.vertical, AdaptiveTheme.spacing4)
                .background(tabBackground)
                .clipShape(RoundedRectangle(cornerRadius: AdaptiveTheme.radiusSmall))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
        }

        @ViewBuilder
        private var tabBackground: some View {
            if tab.isSelected {
                Color.primary.opacity(0.15)
            } else if isHovered {
                Color.primary.opacity(0.07)
            } else {
                Color.clear
            }
        }
    }

    struct CloseTabButton: View {
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isHovered ? .primary : .secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 14, height: 14)
            .background(
                Circle()
                    .fill(Color.primary.opacity(isHovered ? 0.12 : 0))
            )
            .onHover { isHovered = $0 }
        }
    }
}
