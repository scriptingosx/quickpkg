//
//  Extensions.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-08.
//

import Foundation

extension URL {
  var basename: String {
    self.deletingPathExtension().lastPathComponent
  }
}

// from: https://www.swiftbysundell.com/articles/extending-optionals-in-swift/
extension Optional where Wrapped: Collection {
  var isNilOrEmpty: Bool {
    return self?.isEmpty ?? true
  }
}
