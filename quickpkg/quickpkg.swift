//
//  quickpkg.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-08.
//

import Foundation
import ArgumentParser

@main
struct QuickPkg: ParsableCommand {
  static var configuration = CommandConfiguration(
    abstract: "Build installer packages from apps or archives.",
    usage: "quickpkg [options] <installer-item>",
    discussion: "Attempts to build an installation package from the input. Input can be a dmg, zip, or app.",
    version: Constants.version
  )

  @Argument(help: ArgumentHelp(
    "Path to the item to build a installer pkg from.",
    valueName: "installer-item"))
  var itemPath: String

  struct ScriptsOptions: ParsableArguments {
    @Option(name: .customLong("scripts"),
            help: "Path to a folder with scripts.")
    var scriptsFolder: String

    @Option(name: .customLong("preinstall"),
            help: "Path to the preinstall script.")
    var preinstall: String

    @Option(name: .customLong("postinstall"),
            help: "Path to the postinstall script.")
    var postinstall: String
  }

  @OptionGroup(title: "Installation Scripts")
  var scriptsOptions: ScriptsOptions

  @Option(name: .long, help: "Install-location for the resulting pkg.")
  var installLocation: String = "/Applications"

  @Option(help: """
Path where the package file will be created.
You can use '{name}', '{version}' and '{identifier}' as placeholders. If this is a directory, then the package will be created with the default filename {name}-{version}.pkg
""")
  var output: String

  enum Ownership: String, ExpressibleByArgument {
    case recommended, preserve, preserveOther = "preserve-other"
  }

  @Option(name: .long, help: "Sets the ownership.")
  var ownership: Ownership?

  @Flag(inversion: .prefixedNo, help: ArgumentHelp("Clean up temp files.", visibility: .hidden))
  var clean = true

  @Flag(inversion: .prefixedNo, help: "Sets BundleIsRelocatable in the PackageInfo to true.")
  var relocatable = false

  struct SignOptions: ParsableArguments {
    @Option(name: .long, help: "Adds a digital signature to the resulting package.")
    var sign: String

    @Option(name: .long, help: "Specify a specific keychain to search for the signing identity.")
    var keychain: String

    @Option(name: .long, help: "Specify an intermediate certificate to be embedded in the package.")
    var cert: String
  }

  @OptionGroup(title: "Signing")
  var signOptions: SignOptions

  @Flag(name: .shortAndLong, help: "Controls amount of logging output (max -vvv).")
  var verbosity: Int

  func run() {
    print("installer-item: \(itemPath), verbosity: \(verbosity)")
  }
}
