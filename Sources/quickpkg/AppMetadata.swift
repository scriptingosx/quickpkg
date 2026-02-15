import Foundation

struct AppMetadata {
    let name: String
    let identifier: String
    let version: String

    init(from appURL: URL) throws {
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")

        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw QuickPkgError.infoPlistMissing(appURL.path)
        }

        let data = try Data(contentsOf: infoPlistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw QuickPkgError.infoPlistParsingFailed("Invalid plist format")
        }

        // Get name (try CFBundleName, then CFBundleDisplayName, then filename)
        if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
            self.name = bundleName
        } else if let displayName = plist["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            self.name = displayName
        } else {
            // Fall back to filename without extension
            self.name = appURL.deletingPathExtension().lastPathComponent
        }

        // Get identifier
        guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String else {
            throw QuickPkgError.infoPlistParsingFailed("Missing CFBundleIdentifier")
        }
        self.identifier = bundleIdentifier

        // Get version (try CFBundleShortVersionString, then CFBundleVersion)
        if let shortVersion = plist["CFBundleShortVersionString"] as? String, !shortVersion.isEmpty {
            self.version = shortVersion
        } else if let bundleVersion = plist["CFBundleVersion"] as? String, !bundleVersion.isEmpty {
            self.version = bundleVersion
        } else {
            throw QuickPkgError.infoPlistParsingFailed("Missing version information")
        }
    }
}
