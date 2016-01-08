# `quickpkg`

This tool will quickly and easily build a package from an installed application, a disk image file or zip archive with an enclosed application bundle. It will also extract the application name and version and use it to name the resulting `pkg` file. 

The tool will look for applications on the first level of the disk image or archive. If it finds no or more than one application it will error.

The name of the resulting package will be of the form `{name}-{version}.pkg`. Spaces will be removed from the name. The package will be written to the current working directory.

## Examples

Build package from installed application:

```
quickpkg /Applications/Numbers.app
```

Build package from a disk image:

```
quickpkg ~/Downloads/Firefox\ 43.0.4.dmg
```

Build package from a zip archive:

```
quickpkg ~/Downloads/Things.zip
```

## Background

OS X has had the `pkgbuild` tool since Xcode 3.2 on Snow Leopard. With pkgbuild you can directly build a installer package from an application in the `/Applications` folder:

```
pkgbuild --component /Applications/Numbers.app Numbers.pkg
```

Or even an application inside a mounted dmg:

```
pkgbuild --component /Volumes/Firefox/Firefox.app \
         --install-location /Applications \
         Firefox.pkg
```

This tool even does the work of determining a bundle's identifier and version and sets the identifier and version of the pkg to the same values.

However, `pkgbuild` does not automatically name the package.

## `quickpkg` vs `autopkg`

This tool is not meant to replace [`autopkg`](https://github.com/autopkg/autopkg). `autopkg` will automate the download, the re-packaging (if necessary) and the upload to and configuration of your client management system. It can also handle much more complex setups than `quickpkg`. `autopkg` is far superior and should be your tool of choice.

However, there are situations where `autopkg` does not work well. The most common reason is if the download cannot be automated because the download page is behind a paywall. Also `autopkg` requires a recipe for a given piece of software. If no recipe exists, `quickpkg` may be a simple alternative. (Though if `quickpkg` works, creating an `autopkg` recipe should not be hard.) 

## Warning

All `quickpkg` does is identify an application bundle and package it in a way that the package will install that application bundle into the `/Applications` folder. If the application needs other files (libraries, frameworks, configuration files, license files, preferences etc.) to run and work they are your responsibility. 