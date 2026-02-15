import Foundation

struct PackageBuilder: Sendable {
  let executor: ShellExecutor
  let logger: Logger
  
  /// Analyze the payload and create a component plist
  func analyze(
    payloadDir: URL,
    identifier: String,
    version: String,
    installLocation: String,
    outputPlist: URL
  ) async throws {
    let arguments = [
      "/usr/bin/pkgbuild",
      "--analyze",
      "--root", payloadDir.path,
      "--identifier", identifier,
      "--version", version,
      "--install-location", installLocation,
      outputPlist.path
    ]
    
    let result = try await executor.runOrThrow(arguments)
    logger.log(result.stdout, level: 1)
  }
  
  /// Build the package
  func build(
    payloadDir: URL,
    outputPath: String,
    identifier: String,
    version: String,
    installLocation: String,
    scripts: URL?,
    ownership: Ownership?,
    relocatable: Bool,
    sign: String?,
    keychain: String?,
    cert: String?,
    tempDir: URL
  ) async throws {
    // First, create the component plist
    let componentPlist = tempDir.appendingPathComponent("\(identifier).plist")
    try await analyze(
      payloadDir: payloadDir,
      identifier: identifier,
      version: version,
      installLocation: installLocation,
      outputPlist: componentPlist
    )
    
    // Modify relocatable setting if needed
    if !relocatable {
      try PlistHandler.setRelocatable(false, in: componentPlist)
    }
    
    // Build the pkgbuild command
    var arguments = [
      "/usr/bin/pkgbuild",
      "--root", payloadDir.path,
      "--component-plist", componentPlist.path,
      "--identifier", identifier,
      "--version", version,
      "--install-location", installLocation
    ]
    
    if let scriptsDir = scripts {
      arguments += ["--scripts", scriptsDir.path]
      logger.log("Scripts path: \(scriptsDir.path)", level: 1)
    }
    
    if let ownership = ownership {
      arguments += ["--ownership", ownership.rawValue]
    }
    
    if let sign = sign {
      arguments += ["--sign", sign]
    }
    
    if let keychain = keychain {
      arguments += ["--keychain", keychain]
    }
    
    if let cert = cert {
      arguments += ["--cert", cert]
    }
    
    arguments.append(outputPath)
    
    logger.log("Building package: \(outputPath)", level: 1)
    let result = try await executor.run(arguments)
    
    logger.log(result.stdout, level: 1)
    
    if result.exitCode != 0 {
      throw QuickPkgError.pkgbuildFailed("(\(result.exitCode)) \(result.stderr)")
    }
  }
}
