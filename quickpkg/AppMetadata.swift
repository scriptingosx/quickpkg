//
//  AppMetadata.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-09.
//

import Foundation

struct AppMetadata {
  let name: String
  let version: String
  let identifier: String
  let minOSVersion: String

  init?(url: URL) {
    guard let appBundle = Bundle(url: url) else { return nil }

    let identifier = appBundle.bundleIdentifier
    guard identifier != nil else { return nil }
    self.identifier = identifier!

    self.name = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                appBundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                url.basename

    // some apps have _empty_ CFBundleShortVersions
    var version = appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    if version.isNilOrEmpty {
      version = appBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
    self.version = version ?? ""

    // since we are using the minOSVersion for building flat packages, we can default to 10.5
    self.minOSVersion = appBundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "10.5"
  }
}
