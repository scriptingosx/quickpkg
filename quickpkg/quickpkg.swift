//
//  quickpkg.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-08.
//

import Foundation
import ArgumentParser

@main
struct Hello: ParsableCommand {
  func run() {
    print("Hello, quickpkg!")
  }
}
