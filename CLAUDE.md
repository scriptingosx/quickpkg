# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`quickpkg` is a macOS command-line tool that builds installer packages (.pkg files) from applications. It wraps Apple's `pkgbuild` and `productbuild` tools and automatically extracts app metadata (name, version, identifier, minimum OS version) to create properly named packages.

Two implementations exist:
- **Swift** (`Sources/quickpkg/`) - Primary implementation (macOS 15+, Swift 6.0) using swift-argument-parser and swift-subprocess
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

# Build distribution package (default)
.build/debug/quickpkg /Applications/SomeApp.app

# Build component package
.build/debug/quickpkg /Applications/SomeApp.app --component
```

## Architecture

The Swift implementation in `Sources/quickpkg/` follows this flow:

1. `QuickPkg.swift` - Entry point using `AsyncParsableCommand`, parses CLI args
2. `InputType.swift` - Detects input type from file extension (app, dmg, zip, xip); also defines `Ownership`, `Compression`, and `PackageType` enums
3. For archives:
   - `DMGManager.swift` - Actor for mounting/unmounting DMGs via `hdiutil`
   - `ArchiveExtractor.swift` - Handles zip/xip extraction (Sendable)
4. `AppMetadata.swift` - Extracts name/version/identifier/minimumSystemVersion using Bundle API
5. `PackageBuilder.swift` - Runs `pkgbuild --analyze`, removes quarantine attributes, then `pkgbuild` (and `productbuild` for distribution packages)
6. `PlistHandler.swift` - Modifies component plist for non-relocatable packages (Sendable)

Supporting modules:
- `ShellExecutor.swift` - Async subprocess execution wrapper using StringOutput (Sendable)
- `TempDirectory.swift` - Manages temp directories with cleanup
- `Logger.swift` - Verbosity-aware logging (levels 1-3)
- `QuickPkgError.swift` - Error types with LocalizedError conformance
- `URLExtension.swift` - URL extension with `fileExists` property

## Key Design Notes

- **Distribution packages by default** - Uses `productbuild` to wrap the component package (use `--component` for component-only)
- **Non-relocatable by default** - Installer won't search for moved apps (use `--relocatable` to change)
- **Automatic min-os-version** - Extracts `LSMinimumSystemVersion` from app bundle and passes to pkgbuild
- **Quarantine removal** - Removes `com.apple.quarantine` xattr from payload before packaging
- Output naming: `{name}-{version}.pkg` with placeholders `{name}`, `{version}`, `{identifier}`
- DMGManager is an actor to safely manage mount/unmount lifecycle
- All shell commands go through ShellExecutor which logs at verbosity level 3
- Types marked `Sendable` for Swift 6 concurrency safety: `ShellExecutor`, `PackageBuilder`, `PlistHandler`, `ArchiveExtractor`, `Logger`

## Command-Line Options

Key options beyond the Python version:
- `--compression <latest|legacy>` - Compression type for pkgbuild
- `--component` / `--distribution` - Package type (distribution is default)
- `--min-os-version` is automatically extracted from the app's Info.plist

## Scripts

- `pkgAndNotarize.sh` - Build, sign, package, notarize, and staple workflow for creating signed releases

## Code Patterns

- Use `URL(filePath:)` not the deprecated `URL(fileURLWithPath:)`
- Use `url.fileExists` extension instead of `FileManager.default.fileExists(atPath:)`
- Use `Bundle` API for reading app metadata (see `AppMetadata.swift`)
- Use `ArgumentHelp(abstract:discussion:)` for multi-line help text
- Use `EnumerableFlag` for mutually exclusive flags like `--component`/`--distribution`
