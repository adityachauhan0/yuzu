import Foundation

enum ProjectPaths {
    static func projectRootURL(path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func resolve(path: String, in projectPath: String) throws -> URL {
        let root = projectRootURL(path: projectPath)
        let rootPath = root.path
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardizedFileURL
        } else {
            candidate = URL(fileURLWithPath: trimmed, relativeTo: root).standardizedFileURL
        }
        let candidatePath = candidate.path
        if candidatePath == rootPath {
            return candidate
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else {
            throw ProjectPathError.outsideProject(path)
        }
        return candidate
    }
}

enum ProjectPathError: Error, LocalizedError {
    case outsideProject(String)

    var errorDescription: String? {
        switch self {
        case .outsideProject(let path):
            return "Path is outside the project: \(path)"
        }
    }
}
