//
//  Process-Launch.swift
//  ProfilesReader
//
//  Created by Armin Briegel on 2023-05-04.
//

import Foundation

extension String {
  /// convenience initialiser for optional Data; returns nil when the data object is nil */
  init?(data: Data?, encoding: String.Encoding) {
    if let data = data {
      self.init(data: data, encoding: encoding)
    } else {
      return nil
    }
  }
}

// TODO: use this code when we run into threading issues:
// https://developer.apple.com/forums/thread/690310

extension Process {
  /// container struct for the information returned from launch()
  struct LaunchData {
    /// the exit code of the command
    let exitCode: Int
    /// the contents of standard out as Data
    let standardOutData: Data?
    /// the contents of standard error as Data
    let standardErrorData: Data?
    /// the contents of standard out as a utf8 encoded String
    var standardOutString: String? { String(data: standardOutData, encoding: encoding) }
    /// the contents of standard error as a utf8 encoded String
    var standardErrorString: String? { String(data: standardErrorData, encoding: encoding) }

    let encoding: String.Encoding = .utf8
  }

  typealias LaunchResult = Result<LaunchData, Error>

  /// runs the command with the arguments
  /// - Parameters:
  /// - path: absolute file path to the command
  /// - arguments: optional array of arguments for the command
  /// - terminationHandler: code block that is run when command is finished
  static func launch(
    path: String,
    arguments: [String] = [],
    terminationHandler: @escaping (LaunchResult) -> Void
  ) {
    let process = Process()
    let outPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errorPipe
    process.arguments = arguments
    process.launchPath = path
    process.terminationHandler = { process in
      let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
      let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let exitCode = Int(process.terminationStatus)
      let data = LaunchData(
        exitCode: exitCode,
        standardOutData: outData,
        standardErrorData: errorData
      )
      terminationHandler(.success(data))
    }
    do {
      try process.run()
    } catch {
      terminationHandler(.failure(error))
    }
  }

  /// runs the command with the arguments
  /// - Parameters:
  /// - url: file url with the absolute file path to the command
  /// - arguments: optional array of arguments for the command
  /// - terminationHandler: code block that is run when command is finished
  static func launch(
    _ url: URL,
    arguments: [String] = [],
    terminationHandler: @escaping (LaunchResult) -> Void
  ) {
    launch(path: url.path, arguments: arguments, terminationHandler: terminationHandler)
  }

  /// runs the command with the arguments
  /// - Parameters:
  /// - path: absolute file path to the command
  /// - arguments: optional array of arguments for the command
  /// - Returns: LaunchResult struct with the data from the command
  static func launch(
    path: String,
    arguments: [String] = []
  ) async -> (LaunchResult) {
    await withCheckedContinuation { continuation in
      launch(path: path, arguments: arguments) { result in
        continuation.resume(returning: (result))
      }
    }
  }

  /// runs the command with the arguments
  /// - Parameters:
  /// - url: file url with the absolute file path to the command
  /// - arguments: optional array of arguments for the command
  /// - Returns: LaunchResult struct with the data from the command
  static func launch(
    _ url: URL,
    arguments: [String] = []
  ) async -> (LaunchResult) {
    return await launch(path: url.path, arguments: arguments)
  }
}
