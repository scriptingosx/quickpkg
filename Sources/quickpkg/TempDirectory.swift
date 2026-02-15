import Foundation

final class TempDirectory: Sendable {
  let path: URL
  
  init() throws {
    let tempBase = FileManager.default.temporaryDirectory
    self.path = tempBase.appendingPathComponent("quickpkg-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
  }
  
  func cleanup() {
    try? FileManager.default.removeItem(at: path)
  }
}
