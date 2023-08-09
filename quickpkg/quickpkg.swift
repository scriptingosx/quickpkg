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

  // MARK: Arguments and Options

  @Argument(help: ArgumentHelp(
    "Path to the item to build a installer pkg from.",
    valueName: "installer-item"))
  var itemPath: String

  struct ScriptsOptions: ParsableArguments {
    @Option(name: .customLong("scripts"),
            help: "Path to a folder with scripts.")
    var scriptsFolder: String?

    @Option(name: .customLong("preinstall"),
            help: "Path to the preinstall script.")
    var preinstall: String?

    @Option(name: .customLong("postinstall"),
            help: "Path to the postinstall script.")
    var postinstall: String?
  }

  @OptionGroup(title: "Installation Scripts")
  var scriptsOptions: ScriptsOptions

  struct SignOptions: ParsableArguments {
    @Option(name: .long, help: "Adds a digital signature to the resulting package.")
    var sign: String?

    @Option(name: .long, help: "Specify a specific keychain to search for the signing identity.")
    var keychain: String?

    @Option(name: .long, help: "Specify an intermediate certificate to be embedded in the package.")
    var cert: String?
  }

  @OptionGroup(title: "Signing")
  var signOptions: SignOptions

  @Option(name: .long, help: "Install-location for the resulting pkg.")
  var installLocation: String = "/Applications"

  @Option(help: """
Path where the package file will be created.
You can use '{name}', '{version}' and '{identifier}' as placeholders. If this is a directory, then the package will be created with the default filename {name}-{version}.pkg
""")
  var output: String?

  enum Ownership: String, ExpressibleByArgument {
    case recommended, preserve, preserveOther = "preserve-other"
  }

  @Option(name: .long, help: "Sets the ownership.")
  var ownership: Ownership?

  @Flag(inversion: .prefixedNo, help: ArgumentHelp("Clean up temp files.", visibility: .hidden))
  var clean = true

  @Flag(inversion: .prefixedNo, help: "Sets BundleIsRelocatable in the PackageInfo to true.")
  var relocatable = false

  @Flag(name: .shortAndLong, help: "Controls amount of logging output (max -vvv).")
  var verbosity: Int

  // MARK: Properties

  var sourceAppURL: URL?

  lazy var tempDir: URL = {
    var randomNumber = Int.random(in:1000000...9999999)
    var tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "quickpkg.\(randomNumber)",
        isDirectory: true
      )
    while FileManager.default.fileExists(atPath: tempDir.path) {
      randomNumber += 1
      tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "quickpkg.\(randomNumber)",
          isDirectory: true
        )
    }
    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: false)
      return tempDir
    } catch {
      cleanupAndExit("Could not create temporary directory at \(tempDir.path)!", code: 1)
    }
  }()

  lazy var payloadDir: URL = {
    let payloadDir = tempDir.appendingPathComponent("payload", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: false)
      return payloadDir
    } catch {
      cleanupAndExit("Could not create payload directory at \(payloadDir.path)!", code: 1)
    }

  }()

  lazy var scriptsDir: URL = {
    tempDir.appendingPathComponent("scripts", isDirectory: true)
  }()

  lazy var itemURL: URL = URL(filePath: itemPath)


  // MARK: functions

  mutating func cleanupAndExit(_ text: String =  "", code: Int32 = 0) -> Never {
    let message = text.isEmpty ? "Exit Code \(code)" : text
    log(message, level: 0)

    // delete tmp files, respecting options
    if clean {
      try? FileManager.default.removeItem(at: tempDir)
    }

    if code != 0 {
      Self.exit(withError: ExitCode(code))
    }
    Self.exit()
  }

  func log(_ message: String, level: Int = 1) {
    if level <= verbosity {
      print(message)
    }
  }

  // MARK: main
  mutating func run() {
    // remove trailing '/'
    if itemPath.hasSuffix("/") {
      itemPath = String(itemPath.dropLast())
    }

    // expand homedir tilde
    itemPath = NSString(string: itemPath).expandingTildeInPath

    if !Constants.supportedExtensions.contains(itemURL.pathExtension) {
      cleanupAndExit("\(itemURL.pathExtension) is not a supported file type!", code: 1)
    }

    if !FileManager.default.fileExists(atPath: itemPath) {
      cleanupAndExit("Nothing found at \(itemPath)!", code: 41)
    }

    // extract app path from itemPath
    switch itemURL.pathExtension {
    case "app":
      sourceAppURL = itemURL
    default:
      cleanupAndExit("Re-packaging '\(itemURL.pathExtension)' is not implemented yet!", code: 99)
    }

    guard let sourceAppURL else {
      cleanupAndExit("Could not determine app.", code: 4)
    }

    log("found app \(sourceAppURL.path)")

    // copy or move app
    let destAppURL = payloadDir.appendingPathComponent(itemURL.lastPathComponent)
    do {
      log("copying to \(destAppURL.path)")
      try FileManager.default.copyItem(at: sourceAppURL, to: destAppURL)
    } catch {
      cleanupAndExit("could not create a copy of /(sourceAppURL)", code: 5)
    }
    // get metadata from app

    // create the component plist

    // prepare pkgbuild command

    // prepare scripts folder

    // run pkgbuild command

    // cleanup
    cleanupAndExit("Done!")
   }
}
