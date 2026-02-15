# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`quickpkg` is a macOS command-line tool that builds installer packages (.pkg files) from applications. It wraps Apple's `pkgbuild` tool and automatically extracts app metadata (name, version, identifier) to create properly named packages.

Two implementations exist:
- **Swift** (`Sources/quickpkg/`) - Primary implementation (macOS 15+) using swift-argument-parser and swift-subprocess
- **Python** (`quickpkg`) - Original implementation using MacAdmins Managed Python

## Building and Running

```bash
# Build and run
swift build
.build/debug/quickpkg /Applications/SomeApp.app

# Release build
swift build -c release

# Test with verbosity (-v, -vv, or -vvv)
.build/debug/quickpkg -vvv /Applications/SomeApp.app

# Test scripts option
.build/debug/quickpkg /Applications/SomeApp.app --scripts testscripts/
```

## Architecture

The Swift implementation in `Sources/quickpkg/` follows this flow:

1. `QuickPkg.swift` - Entry point using `AsyncParsableCommand`, parses CLI args
2. `InputType.swift` - Detects input type from file extension (app, dmg, zip, xip)
3. For archives:
   - `DMGManager.swift` - Actor for mounting/unmounting DMGs via `hdiutil`
   - `ArchiveExtractor.swift` - Handles zip/xip extraction
4. `AppMetadata.swift` - Extracts name/version/identifier from app's `Info.plist`
5. `PackageBuilder.swift` - Runs `pkgbuild --analyze` then `pkgbuild` to create the pkg
6. `PlistHandler.swift` - Modifies component plist for non-relocatable packages (default)

Supporting modules:
- `ShellExecutor.swift` - Async subprocess execution wrapper
- `TempDirectory.swift` - Manages temp directories with cleanup
- `Logger.swift` - Verbosity-aware logging (levels 1-3)
- `QuickPkgError.swift` - Error types

## Key Design Notes

- Packages are **non-relocatable by default** (installer won't search for moved apps)
- Output naming: `{name}-{version}.pkg` with placeholders `{name}`, `{version}`, `{identifier}`
- DMGManager is an actor to safely manage mount/unmount lifecycle
- All shell commands go through ShellExecutor which logs at verbosity level 3
