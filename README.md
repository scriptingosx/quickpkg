# `quickpkg` - Build packages quickly

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

## Options

### `--scripts scripts_folder`:

Pass a folder with scripts that are passed to `pkgbuild`'s `--scripts` option. If the there is a `preinstall` and/or `postinstall` script they will be run at the respective and can call other scripts in this folder.

### `--postinstall postinstall_script`

Use the script file given as a postinstall script. If given together with the `-scripts` option will attempt to merge the two and error if a `postinstall` script is already present.

### `--preinstall preinstall_script`

Use the script file given as a preinstall script. If given together with the `-scripts` option will attempt to merge the two and error if a `preinstall` script is already present.

### `--ownership {recommended,preserve,preserve-other}`

This parameter will be passed into `pkgbuild`. Default is `recommended`. See `man pkgbuild` for details.

### `--output pkgpath`

Will write the resulting package to `pkgpath` instead of the current working directory. If `pkgpath` is a directory, then the default package name (`{name}-{version}.pkg`) is used. You can also give the complete path, including a name. You can use the placeholders `{name}`, `{version}` and `{identifier}` in the name.

Examples:

```
quickpkg /Applications/Numbers.app --output ~/Packages/
```

Will create `Numbers-X.Y.Z.pkg` in `~/Packages`.

```
quickpkg /Applications/Numbers.app --output Numbers_latest.pkg
```

will create `Numbers_latest.pkg` in the current working directory.

```
quickpkg /Applications/Numbers.app --output ~/Packages/{identifier}_{version}.pkg
```

will create `com.apple.Numbers_X.Y.Z.pkg` in `~/Packages`.

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

However, while `pkgbuild` does automatically name the package, it does not include the version, which is important when you tracking many versions of the same application. It also doesn't automatically look into a `dmg` file or `zip` archive. 

## `quickpkg` vs `autopkg`

This tool is not meant to replace [`autopkg`](https://github.com/autopkg/autopkg). `autopkg` will automate the download, the re-packaging (if necessary) and the upload to and configuration of your client management system. It can also handle much more complex setups than `quickpkg`. `autopkg` is far superior and should be your tool of choice.

However, there are situations where `autopkg` does not work well. The most common reason is if the download cannot be automated because the download page is behind a paywall. Or maybe you are just experimenting with a test server and do not want to change your production `autopkg` setup. Also `autopkg` requires a recipe for a given piece of software. If no recipe exists, `quickpkg` may be a simple alternative. (Though if `quickpkg` works, creating an `autopkg` recipe should not be hard.) 

## `quickpkg` vs `munkipkg`

`quickpkg` is meant for 'quick' packaging. No configuration, no options. Download the application from the AppStore or the dmg or zip from the web and go. (I started working on it because I could never remember the exact options needed for `pkgbuild`.) [`munkipkg`](https://github.com/munki/munki-pkg/) is a tool that makes it easier to access the complex options of `pkgbuild` and `packagebuild`, but it still supports complex projects. 

If you prefer a UI rather than a command line tool, then use [Stéphane Sudre's Packages](http://s.sudre.free.fr/Software/Packages/about.html).

## Warning

All `quickpkg` does is identify an application bundle and package it in a way that the package will install that application bundle into the `/Applications` folder. If the application needs other files (libraries, frameworks, configuration files, license files, preferences etc.) to run and work they are your responsibility.

Also be sure to understand what you are running `quickpkg` against. If you run `quickpkg` on the disk image you get from DropBox or for the Adobe Flash Player, you will get a pkg that installs the DropBox or Flash Player installer in the `/Applications` folder. Probably not what you wanted.