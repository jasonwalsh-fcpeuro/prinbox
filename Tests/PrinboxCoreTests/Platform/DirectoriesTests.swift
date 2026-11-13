import Foundation
import Testing

@testable import PrinboxCore

@Suite struct DirectoriesTests {
    let home = URL(fileURLWithPath: "/Users/dev", isDirectory: true)

    @Test func macPutsConfigUnderDotConfigAndStateUnderApplicationSupport() {
        let dirs = MacDirectories(home: home, environment: [:], bundleID: "io.github.creeonix.prinbox")
        #expect(dirs.config.path == "/Users/dev/.config/prinbox")
        #expect(dirs.state.path == "/Users/dev/Library/Application Support/prinbox")
        #expect(dirs.cache.path == "/Users/dev/Library/Caches/io.github.creeonix.prinbox")
    }

    @Test func macHonorsXDGConfigHome() {
        let dirs = MacDirectories(home: home, environment: ["XDG_CONFIG_HOME": "/tmp/cfg"], bundleID: "x")
        #expect(dirs.config.path == "/tmp/cfg/prinbox")
    }

    @Test func xdgDefaultsFollowTheSpecification() {
        let dirs = XDGDirectories(home: home, environment: [:])
        #expect(dirs.config.path == "/Users/dev/.config/prinbox")
        #expect(dirs.state.path == "/Users/dev/.local/state/prinbox")
        #expect(dirs.cache.path == "/Users/dev/.cache/prinbox")
    }

    @Test func xdgVariablesWinWhenAbsolute() {
        let env = ["XDG_CONFIG_HOME": "/c", "XDG_STATE_HOME": "/s", "XDG_CACHE_HOME": "/k"]
        let dirs = XDGDirectories(home: home, environment: env)
        #expect([dirs.config.path, dirs.state.path, dirs.cache.path] == ["/c/prinbox", "/s/prinbox", "/k/prinbox"])
    }

    @Test func relativeOrEmptyXDGValuesAreIgnored() {
        let env = ["XDG_CONFIG_HOME": "relative/path", "XDG_STATE_HOME": ""]
        let dirs = XDGDirectories(home: home, environment: env)
        #expect(dirs.config.path == "/Users/dev/.config/prinbox")
        #expect(dirs.state.path == "/Users/dev/.local/state/prinbox")
    }

    @Test func stateFileAndAvatarDirectoryHangOffTheAdapter() {
        let dirs = XDGDirectories(home: home, environment: [:])
        #expect(JSONStateFile.url(in: dirs).path == "/Users/dev/.local/state/prinbox/state.json")
        #expect(AvatarCache.directory(in: dirs).path == "/Users/dev/.cache/prinbox/avatars")
    }

    @Test func relativeXDGCacheHomeIsIgnoredToo() {
        let dirs = XDGDirectories(home: home, environment: ["XDG_CACHE_HOME": "relative/cache"])
        #expect(dirs.cache.path == "/Users/dev/.cache/prinbox")
    }

    @Test func profileSeparatesEveryMacDirectory() {
        let dirs = MacDirectories(
            home: home, environment: ["PRINBOX_PROFILE": "fork"], bundleID: "io.github.creeonix.prinbox")
        #expect(dirs.config.path == "/Users/dev/.config/prinbox-fork")
        #expect(dirs.state.path == "/Users/dev/Library/Application Support/prinbox-fork")
        #expect(dirs.cache.path == "/Users/dev/Library/Caches/io.github.creeonix.prinbox.fork")
    }

    @Test func profileSeparatesEveryXDGDirectory() {
        let env = ["PRINBOX_PROFILE": "agent-emacs-keys", "XDG_STATE_HOME": "/s"]
        let dirs = XDGDirectories(home: home, environment: env)
        #expect(dirs.config.path == "/Users/dev/.config/prinbox-agent-emacs-keys")
        #expect(dirs.state.path == "/s/prinbox-agent-emacs-keys")
        #expect(dirs.cache.path == "/Users/dev/.cache/prinbox-agent-emacs-keys")
    }

    @Test func unsafeOrEmptyProfilesAreIgnored() {
        for value in ["", ".", "..", "a/b", "../x", "spa ce", "émoji"] {
            let dirs = XDGDirectories(home: home, environment: ["PRINBOX_PROFILE": value])
            #expect(dirs.state.path == "/Users/dev/.local/state/prinbox", "\(value)")
        }
    }
}
