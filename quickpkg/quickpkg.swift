//
//  quickpkg.swift
//  quickpkg
//
//  Created by Armin Briegel on 2023-08-08.
//

import Foundation
import ArgumentParser

@main
struct QuickPkg: AsyncParsableCommand {
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
You can use '{name}', '{version}' and '{identifier}' as placeholders.
If this is a directory, then the package will be created with the default filename {name}-{version}.pkg
""")
  var output: String?

  enum Ownership: String, ExpressibleByArgument {
    case recommended, preserve, preserveOther = "preserve-other"
  }

  @Option(name: .long, help: "Sets the ownership.")
  var ownership: Ownership?

  @Flag(inversion: .prefixedNo, help: ArgumentHelp("Clean up temp files.", visibility: .hidden))
  var clean = true

  @Flag(inversion: .prefixedNo, help: "Sets BundleIsRelocatable in the PackageInfo.")
  var relocatable = false

  @Flag(name: .shortAndLong, help: "Controls amount of logging output (max -vvv).")
  var verbosity: Int

  // MARK: Properties

  var sourceAppURL: URL?

  lazy var tempDir: URL = {
    var randomNumber = Int.random(in: 1000000...9999999)
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

  mutating func createComponentPlist(app: AppMetadata) async -> URL {
    let plist = tempDir.appending(component: "\(app.identifier).plist")

    let arguments: [String] = [ "--analyze",
                                "--root", payloadDir.path,
                                "--identifier", app.identifier,
                                "--version", app.version,
                                "--install-location", installLocation,
                                plist.path]

    log("Analyzing \(app.name)")
    log("pkgbuild \(arguments.joined(separator: " "))", level: 2)
    let result = await Process.launch(path: Constants.pkgbuild, arguments: arguments)
    switch result {
    case .success(let data):
      if data.exitCode != 0 {
        cleanupAndExit("An error occured while analyzing app.name: \(data.exitCode)", code: 6)
      }

      if !relocatable {
        do {
          let components = try NSMutableArray(contentsOf: plist, error: ())
          for anyComponent in components {
            if let component = anyComponent as? NSMutableDictionary {
              component.setValue(false, forKey: "BundleIsRelocatable")
            }
          }
          try components.write(to: plist)
        } catch {
          cleanupAndExit("Error updating component plist!", code: 6)
        }
      }

      return plist
    case .failure:
      cleanupAndExit("couldn't launch pkgbuild!", code: 5)
    }
  }

  func outputURL(pkgName: String) -> URL {
    // default behavior, create file relative to CWD
    var outputURL: URL = URL(filePath: pkgName, relativeTo: FileManager.default.currentDirectoryURL)
    // if output variable is set, generate based on that
    if let output {
      let expandedOutput = output.expandingTildeInPath
      outputURL = URL(filePath: expandedOutput, relativeTo: FileManager.default.currentDirectoryURL)

      if FileManager.default.fileExistsAndIsDirectory(atPath: outputURL.path) {
        outputURL.append(component: pkgName)
      }

      if outputURL.pathExtension != "pkg" {
        outputURL.appendPathExtension("pkg")
      }
    }
    return outputURL
  }

  mutating func buildPKG(app: AppMetadata) async -> URL {
    // create the component plist
    let componentPlist = await createComponentPlist(app: app)

    // prepare pkgbuild command
    let pkgName = "\(app.name)-\(app.version).pkg".replacingOccurrences(of: " ", with: "")
    // TODO: re-implement substitution logic

    let outputURL = outputURL(pkgName: pkgName)

    var arguments = ["--root", payloadDir.path,
                     "--component-plist", componentPlist.path,
                     "--identifier", app.identifier,
                     "--version", app.version,
                     "--install-location", installLocation,
                     outputURL.path]
    // prepare scripts folder
    // TODO: parse scripts arguments and create folder

    // add signing options
    if let sign = signOptions.sign {
      arguments.append(contentsOf: ["--sign", sign])
    }

    if let keychain = signOptions.keychain {
      arguments.append(contentsOf: ["--keychain", keychain])
    }

    if let cert = signOptions.cert {
      arguments.append(contentsOf: ["--cert", cert])
    }

    // run pkgbuild command
    log("Building \(pkgName)")
    log("pkgbuild \(arguments.joined(separator: " "))", level: 2)
    let result = await Process.launch(path: Constants.pkgbuild, arguments: arguments)
    switch result {
    case .success(let data):
      if verbosity > 0 && !data.standardOutString.isNilOrEmpty {
        print(data.standardOutString ?? "")
      }
      if data.exitCode != 0 {
        cleanupAndExit("Error building pkg!", code: 7)
      }
      return outputURL
    case .failure:
      cleanupAndExit("could not launch pkgbuild", code: 8)
    }
  }

  // MARK: main
  mutating func run() async {
    // remove trailing '/'
    if itemPath.hasSuffix("/") {
      itemPath = String(itemPath.dropLast())
    }

    // expand homedir tilde
    itemPath = itemPath.expandingTildeInPath

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
    case "dmg":
      break
    default:
      cleanupAndExit("Re-packaging '\(itemURL.pathExtension)' is not implemented yet!", code: 99)
    }

    guard let sourceAppURL else {
      cleanupAndExit("Could not determine app.", code: 4)
    }

    log("found app \(sourceAppURL.path)")

    // get metadata from app
    guard let appData = AppMetadata(url: sourceAppURL) else {
      cleanupAndExit("Couldn't get App Metadata", code: 5)
    }

    log("Name: \(appData.name), id: \(appData.identifier), version: \(appData.version), minOS: \(appData.minOSVersion)")

    // copy or move app
    let destAppURL = payloadDir.appendingPathComponent(itemURL.lastPathComponent)
    do {
      log("copying to \(destAppURL.path)")
      try FileManager.default.copyItem(at: sourceAppURL, to: destAppURL)
    } catch {
      cleanupAndExit("could not create a copy of /(sourceAppURL)", code: 5)
    }

    // build pkg
    let outputURL = await buildPKG(app: appData)
    print("Wrote package to \(outputURL.path)")

    // cleanup
    cleanupAndExit("Done!")
   }
}
