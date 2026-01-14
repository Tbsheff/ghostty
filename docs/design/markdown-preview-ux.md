# Markdown Preview Panel UX Specification

## Overview

This document defines the user experience for the markdown preview panel in Ghostty. The design prioritizes keyboard-first interaction, performance, and cohesion with existing Ghostty UI patterns (search overlay, command palette, split panes).

---

## 1. Panel Animation (Show/Hide)

### Entry Animation
- **Trigger**: `Cmd+Shift+M` (macOS) / `Ctrl+Shift+M` (Linux/Windows)
- **Animation**: Slide in from right edge with subtle ease-out curve
- **Duration**: 150ms (matches GTK standard transition timing)
- **Easing**: `ease-out` for entry, `ease-in` for exit

```css
.markdown-panel {
  transition: transform 150ms ease-out, opacity 100ms ease-out;
}

.markdown-panel.hidden {
  transform: translateX(100%);
  opacity: 0;
}

.markdown-panel.visible {
  transform: translateX(0);
  opacity: 1;
}
```

### Panel Sizing
- **Default width**: 40% of terminal window (min: 300px, max: 600px)
- **Resizable**: Drag handle on left edge, consistent with split pane behavior
- **Remember size**: Persist last width per session

### Exit Behavior
- Same keybinding toggles closed
- `Escape` closes panel (returns focus to terminal)
- Closing animation mirrors entry (reverse direction)

---

## 2. Scroll Position Synchronization

### Sync Modes (User Configurable)

| Mode | Behavior | Use Case |
|------|----------|----------|
| `source-driven` | Preview follows source cursor position | Editing markdown |
| `preview-driven` | Source follows preview scroll | Reading/reviewing |
| `independent` | No sync, scroll independently | Side-by-side reference |
| `bidirectional` | Mutual sync with debounce | Default |

### Implementation Details

- **Debounce**: 50ms to prevent jitter during fast scrolling
- **Smooth scroll**: Use `scroll-behavior: smooth` with 100ms duration
- **Visual indicator**: Subtle pulse on synced element when sync occurs
- **Heading anchors**: Clicking TOC in preview scrolls source to heading

### Scroll Position Mapping

```
Source Line -> Preview Position
- Map source line numbers to rendered block positions
- Account for collapsed/expanded blocks
- Handle code blocks (1 source line != 1 preview line)
```

### Visual Feedback
- Thin highlight bar on current synced section (2px, accent color, 30% opacity)
- Fades after 1s of no scroll activity

---

## 3. Click Behavior

### Click-to-Edit (Primary Interaction)

| Element Clicked | Action |
|-----------------|--------|
| Paragraph | Jump to source line, focus terminal |
| Heading | Jump to heading line in source |
| Code block | Jump to code block start line |
| List item | Jump to list item line |
| Table cell | Jump to table row line |

### Visual Affordances
- **Hover state**: Subtle background highlight (`rgba(accent, 0.08)`)
- **Cursor**: `pointer` on interactive elements
- **Tooltip on hover**: "Click to edit (line 42)" - appears after 500ms delay

### Keyboard Navigation
- `Tab` / `Shift+Tab`: Navigate between sections
- `Enter`: Jump to source for focused element
- `j/k` or arrow keys: Scroll preview
- `g g`: Jump to top
- `G`: Jump to bottom
- `/`: Open search within preview

---

## 4. Zoom / Font Size Controls

### Keyboard Shortcuts
- `Cmd/Ctrl + +`: Increase font size
- `Cmd/Ctrl + -`: Decrease font size
- `Cmd/Ctrl + 0`: Reset to default

### Font Size Scale
```
Scale: 10px, 12px, 14px (default), 16px, 18px, 20px, 24px
Step: Variable (smaller steps at lower sizes)
```

### UI Controls
- Header bar contains zoom indicator: "100%" badge
- Click badge to open zoom popover with slider
- Slider range: 50% - 200%

### Persistence
- Zoom level persists per-panel session
- Global default configurable in settings

### Visual Feedback
- Brief toast notification on zoom change: "Zoom: 125%"
- Toast auto-dismisses after 1s
- Toast positioned bottom-center of preview panel

---

## 5. Copy Code Block Functionality

### Trigger Methods
1. **Hover button**: Copy icon appears top-right of code block on hover
2. **Keyboard**: Focus code block with Tab, press `c` or `Enter` then `c`
3. **Right-click**: Context menu with "Copy code" option

### Button Styling
```css
.code-block-copy {
  position: absolute;
  top: 8px;
  right: 8px;
  padding: 4px 8px;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.1);
  opacity: 0;
  transition: opacity 150ms ease;
}

.code-block:hover .code-block-copy {
  opacity: 1;
}

.code-block-copy:hover {
  background: rgba(255, 255, 255, 0.2);
}
```

### Feedback States

| State | Visual | Duration |
|-------|--------|----------|
| Default | Copy icon | - |
| Hover | Highlighted background | - |
| Clicked | Checkmark icon + "Copied!" | 1.5s |
| Error | X icon + "Failed" | 2s |

### Accessibility
- Button has `aria-label="Copy code block"`
- Success/failure announced to screen readers
- Focus visible ring on keyboard navigation

---

## 6. Link Handling

### Link Types and Behaviors

| Link Type | Click Behavior | Modifier + Click |
|-----------|----------------|------------------|
| External URL (`https://`) | Open in default browser | - |
| Internal anchor (`#heading`) | Scroll preview to anchor | - |
| File path (`./file.md`) | Open file in new preview | `Cmd`: Open in editor |
| Relative path (`../other.md`) | Open file in new preview | `Cmd`: Open in editor |

### Visual Indicators
- External links: Subtle external-link icon suffix
- Internal anchors: No icon (underline only)
- File links: File icon prefix

### Confirmation for External Links (Optional Setting)
```
ghostty.markdown.confirm-external-links = true
```
- When enabled, shows tooltip "Press Enter to open in browser"
- Prevents accidental browser opens

### Hover Preview
- Hovering URL shows destination in tooltip after 300ms
- Truncate long URLs: `https://example.com/very/lon...`

### Link Styling
```css
.markdown-link {
  color: var(--accent-color);
  text-decoration: underline;
  text-decoration-color: rgba(var(--accent-rgb), 0.4);
  text-underline-offset: 2px;
}

.markdown-link:hover {
  text-decoration-color: var(--accent-color);
}

.markdown-link.external::after {
  content: url('external-link-symbolic.svg');
  margin-left: 4px;
  opacity: 0.6;
}
```

---

## 7. Image Display and Loading States

### Loading States

```
[Skeleton] -> [Loading] -> [Loaded] or [Error]
```

#### Skeleton State (Immediate)
- Gray placeholder box matching expected aspect ratio
- Subtle shimmer animation (optional, respects `prefers-reduced-motion`)

#### Loading State
- Small spinner in center of placeholder
- Progress indicator for large images (>100KB)

#### Loaded State
- Fade in over 150ms
- Image constrained to panel width with `object-fit: contain`

#### Error State
- Broken image icon with muted styling
- "Image failed to load" text below
- Path shown in monospace: `./images/screenshot.png`
- "Retry" button if network image

### Image Controls (on hover)

| Control | Position | Action |
|---------|----------|--------|
| Zoom in | Top-right | Open image in modal at full size |
| Copy path | Top-right | Copy image path to clipboard |
| Open file | Top-right | Open image in system viewer |

### Modal View (Full-size Image)
- Triggered by click or zoom button
- Dark overlay backdrop (80% opacity)
- Image centered, scrollable if larger than viewport
- `Escape` or click outside to close
- Zoom controls: `+`, `-`, "Fit", "100%"

### Performance Considerations
- Lazy load images below fold
- Thumbnail for images >2MB, load full on demand
- Max render size: 2x panel width (for retina)
- Cache rendered images in memory

---

## 8. Empty State

### When No File Selected

```
+------------------------------------------+
|                                          |
|        [Markdown File Icon]              |
|                                          |
|    No markdown file selected             |
|                                          |
|    Open a .md file to see the preview    |
|    or drag a file here                   |
|                                          |
|    [Browse Files]  [Recent Files v]      |
|                                          |
+------------------------------------------+
```

### Design Specifications
- Icon: 48x48, muted color (40% opacity)
- Primary text: Heading style, normal weight
- Secondary text: Caption style, muted
- Buttons: Ghost style (outlined, no fill)

### Interactions
- "Browse Files" opens file picker filtered to `*.md, *.markdown, *.txt`
- "Recent Files" dropdown shows last 5 viewed markdown files
- Drag-and-drop: Accept `.md` files, show drop zone highlight

### File Watching
- If source file deleted: Show "File not found" state with path
- If file moved: Attempt to track, otherwise show not found

---

## 9. Additional UX Considerations

### Keyboard Shortcut Reference

| Shortcut | Action |
|----------|--------|
| `Cmd/Ctrl+Shift+M` | Toggle panel |
| `Escape` | Close panel / Cancel action |
| `Cmd/Ctrl+0` | Reset zoom |
| `Cmd/Ctrl++/-` | Zoom in/out |
| `Tab/Shift+Tab` | Navigate sections |
| `/` | Search in preview |
| `c` (on code block) | Copy code |
| `o` | Toggle outline/TOC |

### Dark/Light Mode
- Inherit from Ghostty theme
- Code blocks use terminal color scheme
- Respect `prefers-color-scheme`

### High Contrast Mode
- Increase border visibility
- Ensure 4.5:1 contrast minimum (WCAG AA)
- Use `style-hc.css` and `style-hc-dark.css` patterns

### Reduced Motion
- Respect `prefers-reduced-motion`
- Replace animations with instant transitions
- Disable shimmer effects

### Screen Reader Support
- Semantic heading structure preserved
- Code blocks announced with language
- Images have alt text from markdown
- Live regions for copy feedback

---

## 10. State Machine

```
                    +-------------+
                    |   CLOSED    |
                    +------+------+
                           |
                    toggle |
                           v
+-------------+    +-------+-------+    +--------------+
| FILE_ERROR  |<---|    EMPTY      |--->| FILE_LOADING |
+------+------+    +-------+-------+    +------+-------+
       |                   ^                   |
       |                   |                   | loaded
       +---retry-----------+                   v
                                        +------+-------+
                                        |   VIEWING    |
                                        +------+-------+
                                               |
                                          scroll/edit
                                               |
                                        +------v-------+
                                        |   SYNCING    |
                                        +--------------+
```

---

## 11. Configuration Options

```ini
# ghostty config
markdown-preview-width = 400
markdown-preview-position = right  # right | left | bottom
markdown-preview-sync = bidirectional  # source | preview | bidirectional | none
markdown-preview-font-size = 14
markdown-preview-confirm-external-links = false
markdown-preview-lazy-images = true
```

---

## Revision History

| Date | Version | Notes |
|------|---------|-------|
| 2025-01-07 | 1.0 | Initial specification |
