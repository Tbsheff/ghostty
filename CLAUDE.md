# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

| Command | Description |
|---------|-------------|
| `zig build` | Debug build (default) |
| `zig build run` | Build and run Ghostty |
| `zig build test` | Run all unit tests |
| `zig build test -Dtest-filter=<name>` | Run specific tests |
| `zig build run-valgrind` | Memory leak check (Linux) |
| `zig build update-translations` | Update i18n strings |
| `zig fmt .` | Format Zig code |
| `prettier --write .` | Format non-Zig files |
| `alejandra .` | Format Nix files |

**Release builds:** Add `-Doptimize=ReleaseFast`

### libghostty-vt (standalone library)

- Build: `zig build lib-vt`
- Build WASM: `zig build lib-vt -Dtarget=wasm32-freestanding`
- Test: `zig build test-lib-vt`
- When working on libghostty-vt, don't build the full app

### macOS App

- Do NOT use `xcodebuild` directly
- Use `zig build` / `zig build run` for macOS app
- Requires **Xcode 26** and **macOS 26 SDK** (main branch)
- Ensure correct Xcode selected: `sudo xcode-select --switch /Applications/Xcode.app`

### Linux Extra Dependencies

Building from Git checkout requires `blueprint-compiler` >= 0.16.0

## Architecture

```
src/                      # Shared Zig core (~438 files)
├── main.zig              # Entry dispatcher
├── App.zig               # Main application
├── Surface.zig           # Terminal surface (rendering + input)
├── terminal/             # VT emulation (Screen, Parser, PageList)
├── renderer/             # OpenGL (Linux) + Metal (macOS)
├── font/                 # Freetype + HarfBuzz text shaping
├── config/               # Config system (Config.zig is massive)
├── apprt/                # Application runtimes
│   ├── gtk/              # GTK4 Linux/FreeBSD app
│   ├── embedded/         # libghostty embedded mode
│   └── none/             # libghostty standalone
├── build/                # Build system modules
└── cli/                  # CLI subcommands

macos/                    # Native macOS SwiftUI app (~136 Swift files)
├── Sources/App/          # iOS + macOS entries
├── Sources/Features/     # UI: Terminal, Settings, QuickTerminal, Splits
└── Sources/Ghostty/      # Swift<->Zig bridge

pkg/                      # External dependencies (freetype, harfbuzz, etc.)
include/                  # C API headers
```

### Key Patterns

- **Dual renderer:** Metal on macOS, OpenGL on Linux
- **Platform runtimes:** GTK (apprt/gtk) and SwiftUI (macos/) share Zig core
- **Terminal emulation** independent of rendering in `src/terminal/`
- **Config system** is the largest file (~389K); backward compat map exists
- **Multi-threaded:** Dedicated IO thread for PTY, separate render thread

## Logging

```bash
# macOS unified log
sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'

# Linux with systemd
journalctl --user --unit app-com.mitchellh.ghostty.service

# Environment control
GHOSTTY_LOG=stderr,macos  # Enable destinations
GHOSTTY_LOG=no-stderr     # Disable stderr
```

## Agent Commands

Commands in `.agents/commands/` (require `gh` CLI + Nushell):

- `/gh-issue <number/url>` - Diagnose GitHub issue, generate resolution plan (no code)
- `/review-branch [issue]` - Review current branch changes (no code)

## AI Disclosure Requirement

**All AI assistance must be disclosed in PRs.** Test on all impacted platforms—don't use AI to write code for platforms you can't test. Contributors must understand and be able to explain AI-assisted code.

## Version Requirements

- Zig: **0.15.2** minimum
- Xcode: **26** (main branch)
- blueprint-compiler: **0.16.0+** (Linux Git builds)
