import ArgumentParser
import Foundation

enum InputType: String, CaseIterable {
  case app
  case dmg
  case zip
  case xip
  
  static func from(path: String) -> InputType? {
    let ext = URL(filePath: path).pathExtension.lowercased()
    return InputType(rawValue: ext)
  }
}

enum Ownership: String, ExpressibleByArgument, CaseIterable {
  case recommended
  case preserve
  case preserveOther = "preserve-other"
}

enum Compression: String, ExpressibleByArgument, CaseIterable {
  case latest
  case legacy
}

enum PackageType: String, EnumerableFlag {
  case component
  case distribution

  static func name(for value: PackageType) -> NameSpecification {
    .long
  }

  static func help(for value: PackageType) -> ArgumentHelp? {
    switch value {
    case .component:
      return "Build a component package"
    case .distribution:
      return "Build a distribution package using productbuild"
    }
  }
}
