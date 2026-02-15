import Foundation

enum QuickPkgError: LocalizedError {
    case unsupportedExtension(String)
    case fileNotFound(String)
    case noApplicationFound
    case multipleApplicationsFound([String])
    case infoPlistMissing(String)
    case infoPlistParsingFailed(String)
    case dmgMountFailed(String)
    case dmgDetachFailed(String)
    case archiveExtractionFailed(String)
    case pkgbuildFailed(String)
    case scriptNotFound(String)
    case scriptConflict(String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case plistParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return ".\(ext) is not a supported extension! Supported: app, dmg, zip, xip"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .noApplicationFound:
            return "Could not find an application!"
        case .multipleApplicationsFound(let apps):
            return "Found too many applications! Can't decide!\n\(apps.joined(separator: "\n"))"
        case .infoPlistMissing(let path):
            return "Application at \(path) does not have Info.plist"
        case .infoPlistParsingFailed(let reason):
            return "Failed to parse Info.plist: \(reason)"
        case .dmgMountFailed(let reason):
            return "Error mounting disk image: \(reason)"
        case .dmgDetachFailed(let reason):
            return "Error detaching disk image: \(reason)"
        case .archiveExtractionFailed(let reason):
            return "Error extracting archive: \(reason)"
        case .pkgbuildFailed(let reason):
            return "pkgbuild failed: \(reason)"
        case .scriptNotFound(let path):
            return "Script not found: \(path)"
        case .scriptConflict(let reason):
            return "Script conflict: \(reason)"
        case .commandFailed(let command, let exitCode, let stderr):
            return "Command failed (\(exitCode)): \(command)\n\(stderr)"
        case .plistParsingFailed(let reason):
            return "Failed to parse plist: \(reason)"
        }
    }
}
