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
