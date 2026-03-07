import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

struct ArchiveExtractor: Sendable {
  let logger: Logger

  /// Extract a zip archive to the specified directory
  func extractZip(_ archivePath: URL, to destinationDir: URL) async throws {
    logger.log("Extracting zip: \(archivePath.path) to \(destinationDir.path)", level: 1)

    let arguments = ["/usr/bin/unzip", "-q", archivePath.path, "-d", destinationDir.path]
    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)

    let result = try await Subprocess.run(
      .path(FilePath(arguments[0])),
      arguments: Arguments(Array(arguments.dropFirst())),
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.archiveExtractionFailed(result.standardError ?? "unzip failed")
    }
  }

  /// Extract a xip archive to the specified directory
  func extractXip(_ archivePath: URL, to destinationDir: URL) async throws {
    logger.log("Extracting xip: \(archivePath.path) to \(destinationDir.path)", level: 1)

    let arguments = ["/usr/bin/xip", "--expand", archivePath.path]
    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)

    // xip --expand extracts to the current directory, so we need to run it from the destination
    let result = try await Subprocess.run(
      .path(FilePath(arguments[0])),
      arguments: Arguments(Array(arguments.dropFirst())),
      workingDirectory: FilePath(destinationDir.path),
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.archiveExtractionFailed(result.standardError ?? "xip failed")
    }
  }
}
