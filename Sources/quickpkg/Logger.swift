import Foundation

struct Logger: Sendable {
  let verbosity: Int
  
  func log(_ message: String, level: Int = 0) {
    if verbosity >= level {
      print(message)
    }
  }
}
