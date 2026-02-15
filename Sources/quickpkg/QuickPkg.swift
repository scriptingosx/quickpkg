import ArgumentParser
import Foundation

let quickpkgVersion = "2.0.0"

@main
struct QuickPkg: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "quickpkg",
    abstract: "Build packages quickly from applications, disk images, or archives.",
    discussion: """
            Quickly build a package from an installed application, a disk image file,
            or zip/xip archive with an enclosed application bundle.

            The tool extracts the application name and version to name the resulting pkg file.
            """,
    version: quickpkgVersion
  )

  // MARK: - Arguments

  @Argument(help: "Path to the installer item (.app, .dmg, .zip, or .xip)")
  var itemPath: String

  // MARK: - Installation Scripts

  @Option(help: "Path to a folder with scripts")
  var scripts: String?

  @Option(name: [.long, .customLong("pre")], help: "Path to the preinstall script")
  var preinstall: String?

  @Option(name: [.long, .customLong("post")], help: "Path to the postinstall script")
  var postinstall: String?

  // MARK: - Package Options

  @Option(name: .customLong("install-location"), help: "Install location")
  var installLocation: String = "/Applications"

  @Option(help: "Ownership setting: recommended, preserve, or preserve-other")
  var ownership: Ownership?

  @Option(help: "Compression type: latest or legacy")
  var compression: Compression = .latest

  @Option(name: [.customLong("output"), .customLong("out"), .short],
          help: "Output path (supports {name}, {version}, {identifier} placeholders)")
  var output: String?

  // MARK: - Flags

  @Flag(inversion: .prefixedNo, help: "Clean up temp files")
  var clean: Bool = true

  @Flag(inversion: .prefixedNo, help: "Make package relocatable")
  var relocatable: Bool = false

  @Flag(exclusivity: .exclusive)
  var packageType: PackageType = .distribution

  // MARK: - Signing Options

  @Option(help: "Signing identity for the package")
  var sign: String?

  @Option(help: "Keychain to search for signing identity")
  var keychain: String?

  @Option(help: "Intermediate certificate to embed")
  var cert: String?

  // MARK: - Verbosity

  @Flag(name: .shortAndLong, help: "Increase verbosity (-v, -vv, or -vvv)")
  var verbose: Int

  // MARK: - Run

  mutating func run() async throws {
    let logger = Logger(verbosity: verbose)

    // Normalize path
    var path = itemPath
    if path.hasPrefix("~") {
      path = NSString(string: path).expandingTildeInPath
    }
    path = (path as NSString).standardizingPath

    // Remove trailing slash
    if path.hasSuffix("/") {
      path = String(path.dropLast())
    }

    let url = URL(filePath: path)

    // Determine input type
    guard let inputType = InputType.from(path: path) else {
      throw QuickPkgError.unsupportedExtension(url.pathExtension)
    }

    logger.log("Processing \(inputType.rawValue): \(path)", level: 1)

    // Create temp directory for working files
    let tempDir = try TempDirectory()
    defer {
      if clean {
        tempDir.cleanup()
      }
    }

    let executor = ShellExecutor(logger: logger)
    let dmgManager = DMGManager(executor: executor, logger: logger)
    let archiveExtractor = ArchiveExtractor(executor: executor, logger: logger)

    // Capture clean flag for use in async cleanup
    let shouldClean = clean

    // Find the application
    let appURL: URL
    do {
      switch inputType {
      case .app:
        guard FileManager.default.fileExists(atPath: path) else {
          throw QuickPkgError.fileNotFound(path)
        }
        appURL = url

      case .dmg:
        guard FileManager.default.fileExists(atPath: path) else {
          throw QuickPkgError.fileNotFound(path)
        }
        let mountPoints = try await dmgManager.attach(url)
        let apps = findApplications(in: mountPoints)
        guard !apps.isEmpty else {
          throw QuickPkgError.noApplicationFound
        }
        guard apps.count == 1 else {
          throw QuickPkgError.multipleApplicationsFound(apps.map(\.path))
        }
        appURL = apps[0]

      case .zip:
        guard FileManager.default.fileExists(atPath: path) else {
          throw QuickPkgError.fileNotFound(path)
        }
        let extractDir = tempDir.path.appendingPathComponent("unarchive")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await archiveExtractor.extractZip(url, to: extractDir)
        let apps = findApplications(in: [extractDir])
        guard !apps.isEmpty else {
          throw QuickPkgError.noApplicationFound
        }
        guard apps.count == 1 else {
          throw QuickPkgError.multipleApplicationsFound(apps.map(\.path))
        }
        appURL = apps[0]

      case .xip:
        guard FileManager.default.fileExists(atPath: path) else {
          throw QuickPkgError.fileNotFound(path)
        }
        let extractDir = tempDir.path.appendingPathComponent("unarchive")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await archiveExtractor.extractXip(url, to: extractDir)
        let apps = findApplications(in: [extractDir])
        guard !apps.isEmpty else {
          throw QuickPkgError.noApplicationFound
        }
        guard apps.count == 1 else {
          throw QuickPkgError.multipleApplicationsFound(apps.map(\.path))
        }
        appURL = apps[0]
      }
    } catch {
      if shouldClean { await dmgManager.detachAll() }
      throw error
    }

    logger.log("Found application: \(appURL.path)", level: 1)

    // Copy app to payload directory (needed for dmg/zip/xip, and for apps to avoid modifying original)
    let payloadDir = tempDir.path.appendingPathComponent("payload")
    try FileManager.default.createDirectory(at: payloadDir, withIntermediateDirectories: true)
    let payloadAppURL = payloadDir.appendingPathComponent(appURL.lastPathComponent)
    try FileManager.default.copyItem(at: appURL, to: payloadAppURL)

    // Detach DMG now that we've copied the app
    if shouldClean { await dmgManager.detachAll() }

    // Extract metadata from app
    let metadata = try AppMetadata(from: payloadAppURL)
    logger.log("Name: \(metadata.name), ID: \(metadata.identifier), Version: \(metadata.version)", level: 1)
    if let minOS = metadata.minimumSystemVersion {
      logger.log("Minimum macOS: \(minOS)", level: 1)
    }

    // Prepare scripts if needed
    var scriptsDir: URL?
    if let scriptsPath = scripts {
      let scriptsURL = URL(filePath: scriptsPath)
      guard FileManager.default.fileExists(atPath: scriptsPath) else {
        throw QuickPkgError.scriptNotFound(scriptsPath)
      }
      scriptsDir = scriptsURL
    }

    if preinstall != nil || postinstall != nil {
      let tmpScriptsDir = tempDir.path.appendingPathComponent("scripts")
      try FileManager.default.createDirectory(at: tmpScriptsDir, withIntermediateDirectories: true)

      // Copy existing scripts folder if provided
      if let existingScripts = scriptsDir {
        for item in try FileManager.default.contentsOfDirectory(at: existingScripts, includingPropertiesForKeys: nil) {
          try FileManager.default.copyItem(at: item, to: tmpScriptsDir.appendingPathComponent(item.lastPathComponent))
        }
      }

      // Add preinstall script
      if let preinstallPath = preinstall {
        let preinstallURL = URL(filePath: preinstallPath)
        guard FileManager.default.fileExists(atPath: preinstallPath) else {
          throw QuickPkgError.scriptNotFound(preinstallPath)
        }
        let destURL = tmpScriptsDir.appendingPathComponent("preinstall")
        if FileManager.default.fileExists(atPath: destURL.path) {
          throw QuickPkgError.scriptConflict("preinstall script already exists in scripts folder")
        }
        try FileManager.default.copyItem(at: preinstallURL, to: destURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        logger.log("Copied preinstall script to \(destURL.path)", level: 1)
      }

      // Add postinstall script
      if let postinstallPath = postinstall {
        let postinstallURL = URL(filePath: postinstallPath)
        guard FileManager.default.fileExists(atPath: postinstallPath) else {
          throw QuickPkgError.scriptNotFound(postinstallPath)
        }
        let destURL = tmpScriptsDir.appendingPathComponent("postinstall")
        if FileManager.default.fileExists(atPath: destURL.path) {
          throw QuickPkgError.scriptConflict("postinstall script already exists in scripts folder")
        }
        try FileManager.default.copyItem(at: postinstallURL, to: destURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
        logger.log("Copied postinstall script to \(destURL.path)", level: 1)
      }

      scriptsDir = tmpScriptsDir
    }

    // Build the package
    let packageBuilder = PackageBuilder(executor: executor, logger: logger)

    // Determine output path
    let outputPath = determineOutputPath(
      output: output,
      name: metadata.name,
      version: metadata.version,
      identifier: metadata.identifier
    )

    try await packageBuilder.build(
      payloadDir: payloadDir,
      outputPath: outputPath,
      name: metadata.name,
      identifier: metadata.identifier,
      version: metadata.version,
      installLocation: installLocation,
      scripts: scriptsDir,
      ownership: ownership,
      compression: compression,
      relocatable: relocatable,
      minOSVersion: metadata.minimumSystemVersion,
      packageType: packageType,
      sign: sign,
      keychain: keychain,
      cert: cert,
      tempDir: tempDir.path
    )

    print(outputPath)
  }

  // MARK: - Helpers

  private func findApplications(in directories: [URL]) -> [URL] {
    var apps: [URL] = []
    let fm = FileManager.default

    for dir in directories {
      guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
        continue
      }
      for item in contents {
        if item.pathExtension == "app" {
          apps.append(item)
        }
      }
    }

    return apps
  }

  private func determineOutputPath(output: String?, name: String, version: String, identifier: String) -> String {
    let defaultName = "{name}-{version}.pkg"
    var path: String

    if let output = output {
      if FileManager.default.fileExists(atPath: output),
         (try? FileManager.default.attributesOfItem(atPath: output)[.type] as? FileAttributeType) == .typeDirectory {
        path = (output as NSString).appendingPathComponent(defaultName)
      } else {
        path = output
      }
    } else {
      path = defaultName
    }

    // Replace placeholders
    let noSpaceName = name.replacingOccurrences(of: " ", with: "")
    path = path.replacingOccurrences(of: "{name}", with: noSpaceName)
    path = path.replacingOccurrences(of: "{version}", with: version)
    path = path.replacingOccurrences(of: "{identifier}", with: identifier)

    // Ensure .pkg extension
    if !path.hasSuffix(".pkg") {
      path += ".pkg"
    }

    return path
  }
}
