import Foundation

extension URL {
  /// Returns true if this is a file URL and the file exists
  var fileExists: Bool {
    isFileURL && FileManager.default.fileExists(atPath: path)
  }
}
