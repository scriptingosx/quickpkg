import Foundation

struct ArchiveExtractor {
  let executor: ShellExecutor
  let logger: Logger
  
  /// Extract a zip archive to the specified directory
  func extractZip(_ archivePath: URL, to destinationDir: URL) async throws {
    logger.log("Extracting zip: \(archivePath.path) to \(destinationDir.path)", level: 1)
    
    let result = try await executor.run([
      "/usr/bin/unzip",
      "-q",
      archivePath.path,
      "-d", destinationDir.path
    ])
    
    guard result.exitCode == 0 else {
      throw QuickPkgError.archiveExtractionFailed("unzip failed (\(result.exitCode)): \(result.stderr)")
    }
  }
  
  /// Extract a xip archive to the specified directory
  func extractXip(_ archivePath: URL, to destinationDir: URL) async throws {
    logger.log("Extracting xip: \(archivePath.path) to \(destinationDir.path)", level: 1)
    
    // xip --expand extracts to the current directory, so we need to run it from the destination
    let result = try await executor.run(
      ["/usr/bin/xip", "--expand", archivePath.path],
      workingDirectory: destinationDir
    )
    
    guard result.exitCode == 0 else {
      throw QuickPkgError.archiveExtractionFailed("xip failed (\(result.exitCode)): \(result.stderr)")
    }
  }
}
