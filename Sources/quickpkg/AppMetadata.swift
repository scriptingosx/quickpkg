import Foundation

extension Bundle {
  /// Returns CFBundleName, CFBundleDisplayName, or the bundle filename (without extension) as fallback
  var name: String? {
    if let bundleName = object(forInfoDictionaryKey: "CFBundleName") as? String, !bundleName.isEmpty {
      return bundleName
    } else if let displayName = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !displayName.isEmpty {
      return displayName
    } else {
      return bundleURL.deletingPathExtension().lastPathComponent
    }
  }

  /// Returns CFBundleShortVersionString or CFBundleVersion as fallback
  var version: String? {
    if let shortVersion = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !shortVersion.isEmpty {
      return shortVersion
    } else if let bundleVersion = object(forInfoDictionaryKey: "CFBundleVersion") as? String, !bundleVersion.isEmpty {
      return bundleVersion
    }
    return nil
  }

  /// Returns LSMinimumSystemVersion if present
  var minimumSystemVersion: String? {
    object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String
  }
}

struct AppMetadata {
  let name: String
  let identifier: String
  let version: String
  let minimumSystemVersion: String?

  init(from appURL: URL) throws {
    guard let bundle = Bundle(url: appURL) else {
      throw QuickPkgError.infoPlistMissing(appURL.path)
    }

    guard let name = bundle.name else {
      throw QuickPkgError.infoPlistParsingFailed("Missing bundle name")
    }
    self.name = name

    guard let identifier = bundle.bundleIdentifier else {
      throw QuickPkgError.infoPlistParsingFailed("Missing CFBundleIdentifier")
    }
    self.identifier = identifier

    guard let version = bundle.version else {
      throw QuickPkgError.infoPlistParsingFailed("Missing version information")
    }
    self.version = version

    self.minimumSystemVersion = bundle.minimumSystemVersion
  }
}
