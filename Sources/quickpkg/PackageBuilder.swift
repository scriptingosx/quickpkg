import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

struct PackageBuilder: Sendable {
  let logger: Logger

  /// Analyze the payload and create a component plist
  func analyze(
    payloadDir: URL,
    identifier: String,
    version: String,
    installLocation: String,
    outputPlist: URL
  ) async throws {
    let command: FilePath = "/usr/bin/pkgbuild"
    let arguments: Arguments = [
      "--analyze",
      "--root", payloadDir.path,
      "--identifier", identifier,
      "--version", version,
      "--install-location", installLocation,
      outputPlist.path
    ]

    logger.log("Executing: \(command) \(arguments)", level: 2)

    let result = try await Subprocess.run(
      .path(command),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "pkgbuild --analyze failed")
    }
    logger.log("Component plist analysis completed", level: 2)
  }

  /// Build the package
  func build(
    payloadDir: URL,
    outputPath: String,
    name: String,
    identifier: String,
    version: String,
    installLocation: String,
    scripts: URL?,
    ownership: Ownership?,
    compression: Compression,
    relocatable: Bool,
    minOSVersion: String?,
    packageType: PackageType,
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
      logger.log("Setting package as non-relocatable", level: 1)
    }

    // Remove quarantine extended attributes from payload
    logger.log("Removing quarantine attributes from payload", level: 1)
    let xattrCommand: FilePath = "/usr/bin/xattr"
    let xattrArgs: Arguments = ["-dr", "com.apple.quarantine", payloadDir.path]
    logger.log("Executing: \(xattrCommand) \(xattrArgs)", level: 2)
    _ = try await Subprocess.run(
      .path(xattrCommand),
      arguments: xattrArgs,
      output: .discarded,
      error: .discarded
    )

    // Determine output path for pkgbuild (temp location for distribution, final for component)
    let pkgbuildOutput: String
    if packageType == .distribution {
      pkgbuildOutput = tempDir.appendingPathComponent("\(name).pkg").path
    } else {
      pkgbuildOutput = outputPath
    }

    // Build the pkgbuild command
    let pkgbuildCommand: FilePath = "/usr/bin/pkgbuild"
    var pkgbuildArgs: [String] = [
      "--root", payloadDir.path,
      "--component-plist", componentPlist.path,
      "--identifier", identifier,
      "--version", version,
      "--install-location", installLocation
    ]

    if let scriptsDir = scripts {
      pkgbuildArgs += ["--scripts", scriptsDir.path]
      logger.log("Scripts path: \(scriptsDir.path)", level: 1)
    }

    if let ownership = ownership {
      pkgbuildArgs += ["--ownership", ownership.rawValue]
      logger.log("Ownership: \(ownership.rawValue)", level: 1)
    }

    pkgbuildArgs += ["--compression", compression.rawValue]
    logger.log("Compression: \(compression.rawValue)", level: 1)

    if let minOSVersion = minOSVersion {
      pkgbuildArgs += ["--min-os-version", minOSVersion]
      logger.log("Minimum OS version: \(minOSVersion)", level: 1)
    }

    // Only sign with pkgbuild for component packages
    if packageType == .component {
      if let sign = sign {
        pkgbuildArgs += ["--sign", sign]
        logger.log("Signing identity: \(sign)", level: 1)
      }

      if let keychain = keychain {
        pkgbuildArgs += ["--keychain", keychain]
      }

      if let cert = cert {
        pkgbuildArgs += ["--cert", cert]
      }
    }

    pkgbuildArgs.append(pkgbuildOutput)

    logger.log("Building component package: \(pkgbuildOutput)", level: 1)
    let arguments = Arguments(pkgbuildArgs)
    logger.log("Executing: \(pkgbuildCommand) \(arguments)", level: 2)

    let result = try await Subprocess.run(
      .path(pkgbuildCommand),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "pkgbuild failed")
    }
    logger.log("Component package built successfully", level: 2)

    // For distribution packages, run productbuild
    if packageType == .distribution {
      try await buildDistribution(
        componentPackage: pkgbuildOutput,
        outputPath: outputPath,
        identifier: identifier,
        version: version,
        sign: sign,
        keychain: keychain,
        cert: cert
      )
    }
  }

  /// Build a distribution package from a component package
  private func buildDistribution(
    componentPackage: String,
    outputPath: String,
    identifier: String,
    version: String,
    sign: String?,
    keychain: String?,
    cert: String?
  ) async throws {
    let command: FilePath = "/usr/bin/productbuild"
    var productbuildArgs: [String] = [
      "--package", componentPackage,
      "--identifier", identifier,
      "--version", version
    ]

    if let sign = sign {
      productbuildArgs += ["--sign", sign]
    }

    if let keychain = keychain {
      productbuildArgs += ["--keychain", keychain]
    }

    if let cert = cert {
      productbuildArgs += ["--cert", cert]
    }

    productbuildArgs.append(outputPath)

    logger.log("Building distribution package: \(outputPath)", level: 1)
    let arguments = Arguments(productbuildArgs)
    logger.log("Executing: \(command) \(arguments)", level: 2)

    let result = try await Subprocess.run(
      .path(command),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "productbuild failed")
    }
    logger.log("Distribution package built successfully", level: 2)
  }
}
