import ArgumentParser
import Foundation

enum InputType: String, CaseIterable {
    case app
    case dmg
    case zip
    case xip

    static func from(path: String) -> InputType? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return InputType(rawValue: ext)
    }
}

enum Ownership: String, ExpressibleByArgument, CaseIterable {
    case recommended
    case preserve
    case preserveOther = "preserve-other"
}
