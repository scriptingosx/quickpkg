//
//  Extensions.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-08.
//

import Foundation

extension String {
  var expandingTildeInPath: String {
    NSString(string: self).expandingTildeInPath as String
  }
}

extension URL {
  var basename: String {
    self.deletingPathExtension().lastPathComponent
  }
}

extension FileManager {
  var currentDirectoryURL: URL {
    URL(filePath: self.currentDirectoryPath)
  }

  func fileExistsAndIsDirectory(atPath path: String) -> Bool {
    var isDir: ObjCBool = false
    let fileExists = self.fileExists(atPath: path, isDirectory: &isDir)
    return fileExists && isDir.boolValue
  }
}

// from: https://www.swiftbysundell.com/articles/extending-optionals-in-swift/
extension Optional where Wrapped: Collection {
  var isNilOrEmpty: Bool {
    return self?.isEmpty ?? true
  }
}
