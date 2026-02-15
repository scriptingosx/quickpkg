import ArgumentParser
import Foundation

let quickpkgVersion = "2.0.0"

@main
struct QuickPkg: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "quickpkg",
    abstract: "Build packages quickly from installed applications, disk images, or zip archives.",
    discussion: """
            Quickly build a package from an installed application, a disk image file,
            or zip/xip archive with an enclosed application bundle.

            The tool extracts the application name, version, and other metadata from the application
            for the package installer metadata and to name the resulting pkg file.

            Example: quickpkg /path/to/installer_item
            """,
    version: quickpkgVersion
  )

  // MARK: - Arguments

  @Argument(help: "Path to the installer item (.app, .dmg, .zip, or .xip)")
  var itemPath: String

  // MARK: - Installation Scripts

  @Option(help: ArgumentHelp(
    "Path to a folder with scripts.",
    discussion: "If combined with --preinstall or --postinstall, scripts will be merged when possible."))
  var scripts: String?

  @Option(name: [.long, .customLong("pre")], help: "Path to the preinstall script")
  var preinstall: String?

  @Option(name: [.long, .customLong("post")], help: "Path to the postinstall script")
  var postinstall: String?

  // MARK: - Package Options

  @Option(name: .customLong("install-location"), help: "Install location")
  var installLocation: String = "/Applications"

  @Option(help: "Ownership setting")
  var ownership: Ownership?

  @Option(help: "Compression type")
  var compression: Compression = .latest

  @Option(name: [.customLong("output"), .short],
          help: ArgumentHelp(
            "Output path for the package.",
            discussion: "Supports {name}, {version}, {identifier} placeholders. (default filename: {name}-{version}.pkg)"))
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

    // Normalize path and determine input type
    let path = normalizePath(itemPath)
    let url = URL(filePath: path)

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
      appURL = try await findApplication(
        at: url,
        inputType: inputType,
        tempDir: tempDir,
        dmgManager: dmgManager,
        archiveExtractor: archiveExtractor
      )
    } catch {
      if shouldClean { await dmgManager.detachAll() }
      throw error
    }

    logger.log("Found application: \(appURL.path)", level: 1)

    // Copy app to payload directory
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
    let scriptsDir = try prepareScripts(tempDir: tempDir, logger: logger)

    // Build the package
    let packageBuilder = PackageBuilder(executor: executor, logger: logger)
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

  /// Normalize a file path (expand tilde, standardize, remove trailing slash)
  private func normalizePath(_ path: String) -> String {
    var result = path
    if result.hasPrefix("~") {
      result = NSString(string: result).expandingTildeInPath
    }
    result = (result as NSString).standardizingPath
    if result.hasSuffix("/") {
      result = String(result.dropLast())
    }
    return result
  }

  /// Find applications in the given directories
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

  /// Validate exactly one application exists and return it
  private func validateSingleApplication(in directories: [URL]) throws -> URL {
    let apps = findApplications(in: directories)
    guard !apps.isEmpty else {
      throw QuickPkgError.noApplicationFound
    }
    guard apps.count == 1 else {
      throw QuickPkgError.multipleApplicationsFound(apps.map(\.path))
    }
    return apps[0]
  }

  /// Find the application from the input source
  private func findApplication(
    at url: URL,
    inputType: InputType,
    tempDir: TempDirectory,
    dmgManager: DMGManager,
    archiveExtractor: ArchiveExtractor
  ) async throws -> URL {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw QuickPkgError.fileNotFound(url.path)
    }

    switch inputType {
    case .app:
      return url

    case .dmg:
      let mountPoints = try await dmgManager.attach(url)
      return try validateSingleApplication(in: mountPoints)

    case .zip:
      let extractDir = tempDir.path.appendingPathComponent("unarchive")
      try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
      try await archiveExtractor.extractZip(url, to: extractDir)
      return try validateSingleApplication(in: [extractDir])

    case .xip:
      let extractDir = tempDir.path.appendingPathComponent("unarchive")
      try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
      try await archiveExtractor.extractXip(url, to: extractDir)
      return try validateSingleApplication(in: [extractDir])
    }
  }

  /// Prepare the scripts directory, merging --scripts with --preinstall/--postinstall if needed
  private func prepareScripts(tempDir: TempDirectory, logger: Logger) throws -> URL? {
    var scriptsDir: URL?

    if let scriptsPath = scripts {
      let scriptsURL = URL(filePath: scriptsPath)
      guard FileManager.default.fileExists(atPath: scriptsPath) else {
        throw QuickPkgError.scriptNotFound(scriptsPath)
      }
      scriptsDir = scriptsURL
    }

    guard preinstall != nil || postinstall != nil else {
      return scriptsDir
    }

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
      try copyScript(from: preinstallPath, to: tmpScriptsDir, name: "preinstall", logger: logger)
    }

    // Add postinstall script
    if let postinstallPath = postinstall {
      try copyScript(from: postinstallPath, to: tmpScriptsDir, name: "postinstall", logger: logger)
    }

    return tmpScriptsDir
  }

  /// Copy a script to the scripts directory with proper permissions
  private func copyScript(from sourcePath: String, to scriptsDir: URL, name: String, logger: Logger) throws {
    let sourceURL = URL(filePath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourcePath) else {
      throw QuickPkgError.scriptNotFound(sourcePath)
    }
    let destURL = scriptsDir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destURL.path) {
      throw QuickPkgError.scriptConflict("\(name) script already exists in scripts folder")
    }
    try FileManager.default.copyItem(at: sourceURL, to: destURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destURL.path)
    logger.log("Copied \(name) script to \(destURL.path)", level: 1)
  }

  /// Determine the output path for the package
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
