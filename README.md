# `quickpkg` - Build packages quickly

This tool will quickly and easily build a package from an installed application, a disk image file, or zip/xip archive with an enclosed application bundle. It will also extract the application name, version, identifier, and minimum OS version and use them for the resulting `pkg` file.

The tool will look for applications on the first level of the disk image or archive. If it finds no or more than one application it will error.

The name of the resulting package will be of the form `{name}-{version}.pkg`. Spaces will be removed from the name. The package will be written to the current working directory.

## Installation

Download the [quickpkg installer](https://github.com/scriptingosx/quickpkg/releases/latest). The `quickpkg` binary will be installed in `/usr/local/bin/quickpkg`. Run `quickpkg --help` for details.

## Examples

Build package from installed application:

```
quickpkg /Applications/Numbers.app
```

Build package from a disk image:

```
quickpkg ~/Downloads/Firefox.dmg
```

Build package from a zip archive:

```
quickpkg ~/Downloads/Things.zip
```

Build package from an xip archive:

```
quickpkg ~/Downloads/Xcode.xip
```

Build a signed distribution package:

```
quickpkg /Applications/MyApp.app --sign "Developer ID Installer: Your Name"
```

Build a component package (instead of distribution):

```
quickpkg /Applications/MyApp.app --component
```

## Options

### Installation Scripts

#### `--scripts <folder>`

Pass a folder with scripts that are passed to `pkgbuild`'s `--scripts` option. If there is a `preinstall` and/or `postinstall` script they will be run at the respective times and can call other scripts in this folder.

#### `--postinstall <script>` (or `--post`)

Use the script file given as a postinstall script. If given together with the `--scripts` option will attempt to merge the two and error if a `postinstall` script is already present.

#### `--preinstall <script>` (or `--pre`)

Use the script file given as a preinstall script. If given together with the `--scripts` option will attempt to merge the two and error if a `preinstall` script is already present.

### Package Options

#### `--install-location <path>`

Set the install location for the application. Default is `/Applications`.

#### `--ownership <recommended|preserve|preserve-other>`

This parameter will be passed to `pkgbuild`. See `man pkgbuild` for details.

#### `--compression <latest|legacy>` (v2.0)

Set the compression type for the package. Default is `latest`.

#### `--component` / `--distribution` (v2.0)

Choose the package type. Default is `--distribution` which wraps the component package using `productbuild`. Use `--component` for a simple component package.

#### `--[no-]relocatable`

Controls whether the resulting pkg file is relocatable, i.e. if the installer process will search for the bundle by bundle-identifier if it was moved to another location. By default packages are created **non-relocatable**.

#### `--[no-]clean`

Controls whether temporary files are cleaned up after building. Default is `--clean`.

### Output Options

#### `--output <path>` (or `-o`)

Write the resulting package to `<path>` instead of the current working directory. If `<path>` is a directory, then the default package name (`{name}-{version}.pkg`) is used. You can also give the complete path, including a name. You can use the placeholders `{name}`, `{version}` and `{identifier}` in the name.

Examples:

```
quickpkg /Applications/Numbers.app --output ~/Packages/
```

Will create `Numbers-X.Y.Z.pkg` in `~/Packages`.

```
quickpkg /Applications/Numbers.app --output Numbers_latest.pkg
```

Will create `Numbers_latest.pkg` in the current working directory.

```
quickpkg /Applications/Numbers.app --output ~/Packages/{identifier}_{version}.pkg
```

Will create `com.apple.Numbers_X.Y.Z.pkg` in `~/Packages`.

### Signing Options

#### `--sign <identity>`

Sign the resulting package with the specified identity. Usually a "Developer ID Installer" certificate from your Apple Developer account.

#### `--keychain <path>`

Specify a keychain to search for the signing identity.

#### `--cert <path>`

Specify an intermediate certificate to embed in the package.

You can find available signing identities with:

```
security find-identity -p basic -v
```

Example:

```
quickpkg ~/Downloads/Firefox.dmg --sign "Developer ID Installer: Your Name"
```

### Verbosity

#### `-v`, `-vv`, `-vvv`

Increase verbosity. Use `-v` for basic info, `-vv` for more detail, `-vvv` for full command output including all shell commands.

## Background

macOS has had the `pkgbuild` tool since Xcode 3.2 on Snow Leopard. With pkgbuild you can directly build an installer package from an application in the `/Applications` folder:

```
pkgbuild --component /Applications/Numbers.app Numbers.pkg
```

Or even an application inside a mounted dmg:

```
pkgbuild --component /Volumes/Firefox/Firefox.app \
         --install-location /Applications \
         Firefox.pkg
```

`pkgbuild` even does the work of determining a bundle's identifier, version, and minimum supported OS version and sets the attributes of the pkg to the same values.

However, `pkgbuild` does not automatically create the pkg's filename, determine minimum OS version. Also, you often need a distribution pkg/product archive which requires an extra step to wrap the component package. I built `quickpkg` to simplify this workflow. `quickpkg` can also automatically unarchive and repackage apps delivered in dmg, zip, or xip archives. 

## A Note on Notarization

`quickpkg` does not support notarization. Apple's notarization process requires that the application inside the package is signed with the same Developer ID as the package itself. Since `quickpkg` is designed to repackage third-party applications that you don't control the code signing for, notarization is not recommended or possible for packages created with this tool.

## Warning

All `quickpkg` does is identify an application bundle and package it in a way that the package will install that application bundle into the `/Applications` folder (or another location specified with `--install-location`). If the application needs other files (libraries, frameworks, configuration files, license files, preferences etc.) to run and work they are your responsibility.

Also be sure to understand what you are running `quickpkg` against. For example, when you run `quickpkg` on the disk image you get from DropBox, you will get a pkg that installs the DropBox installer in the `/Applications` folder. Probably not what you wanted.

## `quickpkg` vs `autopkg`

This tool is not meant to replace [`autopkg`](https://github.com/autopkg/autopkg). `autopkg` will automate the download, the re-packaging (if necessary) and the upload to and configuration of your client management system. It can also handle much more complex setups than `quickpkg`. `autopkg` is far superior and should be your tool of choice.

On the other hand, autopkg requires a certain expertise and a dedicated setup which needs to be maintained. Sometimes a 'quick' re-packaging is just easier.

There are also situations where `autopkg` does not work well. The most common reason is if the download cannot be automated because the download page is behind a paywall or similar restriction. Or maybe you are just experimenting with a test server and do not want to change your production `autopkg` setup. Also `autopkg` requires a recipe for a given piece of software. If no recipe exists, `quickpkg` may be a simple alternative. (Though if `quickpkg` works, creating an `autopkg` recipe should not be hard.)
