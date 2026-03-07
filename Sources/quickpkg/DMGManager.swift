import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

actor DMGManager {
  private let logger: Logger
  private var wasMounted: [URL: Bool] = [:]
  private var mountedVolumes: [URL] = []

  init(logger: Logger) {
    self.logger = logger
  }

  /// Check if a DMG has a Software License Agreement
  func hasSLA(at path: URL) async throws -> Bool {
    let command: FilePath = "/usr/bin/hdiutil"
    let arguments: Arguments = ["imageinfo", path.path, "-plist"]
    logger.log("Executing: \(command) \(arguments)", level: 3)

    let result = try await Subprocess.run(
      .path(command),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.dmgMountFailed(result.standardError ?? "hdiutil imageinfo failed")
    }

    let plist = try PlistHandler.parse(Data((result.standardOutput ?? "").utf8))
    if let properties = plist["Properties"] as? [String: Any],
       let hasSLA = properties["Software License Agreement"] as? Bool {
      return hasSLA
    }
    return false
  }

  /// Check if DMG is already mounted and return mount points
  func existingMountPoints(for dmgPath: URL) async throws -> [URL]? {
    let command: FilePath = "/usr/bin/hdiutil"
    let arguments: Arguments = ["info", "-plist"]
    logger.log("Executing: \(command) \(arguments)", level: 3)

    let result = try await Subprocess.run(
      .path(command),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    guard result.terminationStatus.isSuccess else {
      throw QuickPkgError.dmgMountFailed(result.standardError ?? "hdiutil info failed")
    }

    let plistData = try PlistHandler.extractFirstPlist(from: Data((result.standardOutput ?? "").utf8))
    let info = try PlistHandler.parse(plistData)

    guard let images = info["images"] as? [[String: Any]] else {
      return nil
    }

    for image in images {
      guard let imagePath = image["image-path"] as? String else { continue }

      // Check if this is our DMG (compare paths)
      let imageURL = URL(filePath: imagePath)
      if imageURL.standardizedFileURL == dmgPath.standardizedFileURL ||
          FileManager.default.contentsEqual(atPath: imageURL.path, andPath: dmgPath.path) {

        var mountPoints: [URL] = []
        if let entities = image["system-entities"] as? [[String: Any]] {
          for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
              mountPoints.append(URL(filePath: mountPoint))
            }
          }
        }

        if !mountPoints.isEmpty {
          // Mark as pre-mounted so we don't detach it
          for mp in mountPoints {
            wasMounted[mp] = true
          }
          return mountPoints
        }
      }
    }

    return nil
  }

  /// Attach a DMG and return mount points
  func attach(_ dmgPath: URL) async throws -> [URL] {
    // First check if already mounted
    if let existing = try await existingMountPoints(for: dmgPath) {
      logger.log("DMG already mounted at: \(existing.map(\.path).joined(separator: ", "))", level: 1)
      return existing
    }

    // Check for SLA
    let sla = try await hasSLA(at: dmgPath)
    if sla {
      logger.log("NOTE: Disk image \(dmgPath.path) has a license agreement!", level: 0)
    }

    // Mount the DMG
    let command: FilePath = "/usr/bin/hdiutil"
    let arguments: Arguments = [
      "attach",
      dmgPath.path,
      "-mountrandom", "/private/tmp",
      "-plist",
      "-nobrowse"
    ]

    logger.log("Executing: \(command) \(arguments)", level: 3)

    let terminationStatus: TerminationStatus
    let standardOutput: String?
    let standardError: String?

    if sla {
      let result = try await Subprocess.run(
        .path(command),
        arguments: arguments,
        input: .string("Y\n"),
        output: .string(limit: .max),
        error: .string(limit: .max)
      )
      terminationStatus = result.terminationStatus
      standardOutput = result.standardOutput
      standardError = result.standardError
    } else {
      let result = try await Subprocess.run(
        .path(command),
        arguments: arguments,
        output: .string(limit: .max),
        error: .string(limit: .max)
      )
      terminationStatus = result.terminationStatus
      standardOutput = result.standardOutput
      standardError = result.standardError
    }

    guard terminationStatus.isSuccess else {
      throw QuickPkgError.dmgMountFailed(standardError ?? "hdiutil attach failed")
    }

    // Parse the plist output to get mount points
    let plistData = try PlistHandler.extractFirstPlist(from: Data((standardOutput ?? "").utf8))
    let attachResult = try PlistHandler.parse(plistData)

    var mountPoints: [URL] = []
    if let entities = attachResult["system-entities"] as? [[String: Any]] {
      for entity in entities {
        if let potentiallyMountable = entity["potentially-mountable"] as? Bool,
           potentiallyMountable,
           let volumeKind = entity["volume-kind"] as? String,
           volumeKind == "hfs" || volumeKind == "apfs",
           let mountPoint = entity["mount-point"] as? String {
          let url = URL(filePath: mountPoint)
          mountPoints.append(url)
          mountedVolumes.append(url)
          wasMounted[url] = false
        }
      }
    }

    logger.log("Mounted DMG at: \(mountPoints.map(\.path).joined(separator: ", "))", level: 1)
    return mountPoints
  }

  /// Detach a mounted volume
  func detach(_ mountPoint: URL) async throws {
    // Don't detach if it was already mounted before we started
    if wasMounted[mountPoint] == true {
      logger.log("Skipping detach for pre-mounted volume: \(mountPoint.path)", level: 2)
      return
    }

    guard mountPoint.fileExists else { return }

    let command: FilePath = "/usr/bin/hdiutil"
    let arguments: Arguments = ["detach", mountPoint.path]
    logger.log("Executing: \(command) \(arguments)", level: 3)

    let result = try await Subprocess.run(
      .path(command),
      arguments: arguments,
      output: .string(limit: .max),
      error: .string(limit: .max)
    )

    if !result.terminationStatus.isSuccess {
      logger.log("Warning: Failed to detach \(mountPoint.path): \(result.standardError ?? "")", level: 1)
    } else {
      logger.log("Detached: \(mountPoint.path)", level: 2)
    }

    mountedVolumes.removeAll { $0 == mountPoint }
    wasMounted.removeValue(forKey: mountPoint)
  }

  /// Detach all volumes that we mounted
  func detachAll() async {
    for volume in mountedVolumes {
      if wasMounted[volume] != true {
        try? await detach(volume)
      }
    }
  }
}
