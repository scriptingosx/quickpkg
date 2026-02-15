import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

struct ShellExecutor: Sendable {
  let logger: Logger
  
  struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
  }
  
  func run(_ arguments: [String], input inputString: String? = nil, workingDirectory: URL? = nil) async throws -> CommandResult {
    logger.log("Executing: \(arguments.joined(separator: " "))", level: 3)
    
    guard let executable = arguments.first else {
      throw QuickPkgError.commandFailed(command: "", exitCode: -1, stderr: "No command specified")
    }
    
    let args = Array(arguments.dropFirst())
    let maxOutputSize = 10 * 1024 * 1024  // 10 MB limit
    let workDir = workingDirectory.map { FilePath($0.path) }
    
    let result: CollectedResult<StringOutput<UTF8>, StringOutput<UTF8>>
    
    let input: InputProtocol
    if let inputString {
      input = .string(inputString)
    } else {
      input = .none
    }
    
    result = try await Subprocess.run(
      .path(FilePath(executable)),
      arguments: Arguments(args),
      workingDirectory: workDir,
      input: input,
      output: .string(limit: maxOutputSize, encoding: UTF8.self),
      error: .string(limit: maxOutputSize, encoding: UTF8.self)
    )
    
    
    let stdout = (result.standardOutput ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let stderr = (result.standardError ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    
    let exitCode: Int32
    switch result.terminationStatus {
    case .exited(let code):
      exitCode = code
    case .unhandledException(let code):
      exitCode = code
    }
    
    return CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
  }
  
  func runOrThrow(_ arguments: [String], input: String? = nil, workingDirectory: URL? = nil) async throws -> CommandResult {
    let result = try await run(arguments, input: input, workingDirectory: workingDirectory)
    
    logger.log("Exit code: \(result.exitCode)", level: 3)
    if !result.stdout.isEmpty {
      logger.log("stdout: \(result.stdout)", level: 3)
    }
    if !result.stderr.isEmpty {
      logger.log("stderr: \(result.stderr)", level: 3)
    }
    
    guard result.exitCode == 0 else {
      throw QuickPkgError.commandFailed(
        command: arguments.joined(separator: " "),
        exitCode: result.exitCode,
        stderr: result.stderr
      )
    }
    return result
  }
}
