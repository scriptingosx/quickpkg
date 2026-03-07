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
    let arguments = [
      "/usr/bin/pkgbuild",
      "--analyze",
      "--root", payloadDir.path,
      "--identifier", identifier,
      "--version", version,
      "--install-location", installLocation,
      outputPlist.path
    ]

    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)

    let result = try await Subprocess.run(
      .path(FilePath(arguments[0])),
      arguments: Arguments(Array(arguments.dropFirst())),
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "pkgbuild --analyze failed")
    }
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
    }

    // Remove quarantine extended attributes from payload
    logger.log("Removing quarantine attributes from payload", level: 1)
    let xattrArgs = ["/usr/bin/xattr", "-dr", "com.apple.quarantine", payloadDir.path]
    logger.log("Executing: \(xattrArgs.joined(separator: " "))", level: 3)
    _ = try await Subprocess.run(
      .path(FilePath(xattrArgs[0])),
      arguments: Arguments(Array(xattrArgs.dropFirst())),
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

    arguments += ["--compression", compression.rawValue]

    if let minOSVersion = minOSVersion {
      arguments += ["--min-os-version", minOSVersion]
      logger.log("Minimum OS version: \(minOSVersion)", level: 1)
    }

    // Only sign with pkgbuild for component packages
    if packageType == .component {
      if let sign = sign {
        arguments += ["--sign", sign]
      }

      if let keychain = keychain {
        arguments += ["--keychain", keychain]
      }

      if let cert = cert {
        arguments += ["--cert", cert]
      }
    }

    arguments.append(pkgbuildOutput)

    logger.log("Building component package: \(pkgbuildOutput)", level: 1)
    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)

    let result = try await Subprocess.run(
      .path(FilePath(arguments[0])),
      arguments: Arguments(Array(arguments.dropFirst())),
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "pkgbuild failed")
    }

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
    var arguments = [
      "/usr/bin/productbuild",
      "--package", componentPackage,
      "--identifier", identifier,
      "--version", version
    ]

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

    logger.log("Building distribution package: \(outputPath)", level: 1)
    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)

    let result = try await Subprocess.run(
      .path(FilePath(arguments[0])),
      arguments: Arguments(Array(arguments.dropFirst())),
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.pkgbuildFailed(result.standardError ?? "productbuild failed")
    }
  }
}
