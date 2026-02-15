import Foundation

struct PlistHandler: Sendable {
  /// Extract the first plist from mixed output (like hdiutil which returns text + plist)
  static func extractFirstPlist(from data: Data) throws -> Data {
    guard let string = String(data: data, encoding: .utf8) else {
      throw QuickPkgError.plistParsingFailed("Invalid UTF-8 data")
    }

    let header = "<?xml version"
    let footer = "</plist>"

    guard let startRange = string.range(of: header),
          let endRange = string.range(of: footer, range: startRange.upperBound..<string.endIndex) else {
      throw QuickPkgError.plistParsingFailed("No plist found in output")
    }

    let plistString = String(string[startRange.lowerBound..<endRange.upperBound]) + "\n"
    return Data(plistString.utf8)
  }

  /// Parse plist data into a dictionary
  static func parse(_ data: Data) throws -> [String: Any] {
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
      throw QuickPkgError.plistParsingFailed("Invalid plist format - expected dictionary")
    }
    return plist
  }

  /// Parse plist data into an array of dictionaries
  static func parseArray(_ data: Data) throws -> [[String: Any]] {
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
      throw QuickPkgError.plistParsingFailed("Invalid plist format - expected array")
    }
    return plist
  }

  /// Modify component plist to set BundleIsRelocatable
  static func setRelocatable(_ relocatable: Bool, in plistURL: URL) throws {
    let data = try Data(contentsOf: plistURL)
    var components = try parseArray(data)

    for i in components.indices {
      if components[i]["BundleIsRelocatable"] != nil {
        components[i]["BundleIsRelocatable"] = relocatable
      }
    }

    let outputData = try PropertyListSerialization.data(
      fromPropertyList: components,
      format: .xml,
      options: 0
    )
    try outputData.write(to: plistURL)
  }
}
