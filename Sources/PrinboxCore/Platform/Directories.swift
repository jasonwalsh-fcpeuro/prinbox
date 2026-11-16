import Foundation

/// Where the three kinds of files live. Both adapters are plain Foundation and compile everywhere; the
/// composition roots choose: the app and the command on macOS take `MacDirectories`, the command on Linux
/// `XDGDirectories`.
public protocol Directories: Sendable {
    /// `settings.json`.
    var config: URL { get }
    /// `state.json`, `cache.json`, `update.json`, `prinbox.lock`.
    var state: URL { get }
    /// Avatars.
    var cache: URL { get }
}

/// macOS: config under `~/.config` (or `$XDG_CONFIG_HOME`), state in Application Support, caches in Caches.
public struct MacDirectories: Directories {
    public let config: URL
    public let state: URL
    public let cache: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleID: String = "io.github.creeonix.prinbox"
    ) {
        let name = XDGDirectories.name(environment)
        let suffix = XDGDirectories.profile(environment).map { ".\($0)" } ?? ""
        config = XDGDirectories.base(environment["XDG_CONFIG_HOME"], default: home.appendingPathComponent(".config"))
            .appendingPathComponent(name, isDirectory: true)
        state = home.appendingPathComponent("Library/Application Support/\(name)", isDirectory: true)
        cache = home.appendingPathComponent("Library/Caches/\(bundleID)\(suffix)", isDirectory: true)
    }
}

/// Linux: the XDG base directories with their standard defaults.
public struct XDGDirectories: Directories {
    public let config: URL
    public let state: URL
    public let cache: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let name = Self.name(environment)
        config = Self.base(environment["XDG_CONFIG_HOME"], default: home.appendingPathComponent(".config"))
            .appendingPathComponent(name, isDirectory: true)
        state = Self.base(environment["XDG_STATE_HOME"], default: home.appendingPathComponent(".local/state"))
            .appendingPathComponent(name, isDirectory: true)
        cache = Self.base(environment["XDG_CACHE_HOME"], default: home.appendingPathComponent(".cache"))
            .appendingPathComponent(name, isDirectory: true)
    }

    /// `PRINBOX_PROFILE`: a separate set of directories (settings, snoozes, cache, lock) per profile, so a
    /// development build or a test run never shares state with the everyday install. Letters, digits,
    /// `.`, `_` and `-` only; anything else, `.` or `..` is ignored.
    static func profile(_ environment: [String: String]) -> String? {
        guard let value = environment["PRINBOX_PROFILE"], !value.isEmpty, value != ".", value != "..",
            value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
        else { return nil }
        return value
    }

    /// `prinbox`, or `prinbox-<profile>`.
    static func name(_ environment: [String: String]) -> String {
        profile(environment).map { "prinbox-\($0)" } ?? "prinbox"
    }

    /// The specification: an unset, empty or relative value is ignored.
    static func base(_ value: String?, default fallback: URL) -> URL {
        guard let value, value.hasPrefix("/") else { return fallback }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
