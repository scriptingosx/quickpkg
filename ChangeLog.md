# Change Log – utiluti

## v2.0.1

(2026-03-13)

- no new features
- general code cleanup
- there are now only two log levels (`-v` and `-vv`)

## v2.0.0

(2026-02-15)

No more python dependency, complete re-write in Swift.

## New Features

- builds distribution packages by default (use `--component` option to revert to building component packages)
- gathers minimum required OS version from the app bundle and applies that to the package
- applies `--compression latest` for better pkg compression (use `--compression legacy` to override)
- quarantine flags are removed from the payload before creating the package

## Python versions (1.0 and older)

for earlier release notes, [check the repo](https://github.com/scriptingosx/quickpkg/releases)
