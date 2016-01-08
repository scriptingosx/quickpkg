# quickpkg

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

However, `pkgbuild` does not 