import Testing
import Foundation
@testable import Capture

@Suite struct ProcessCatalogTests {
    @Test func discordFixture() {
        let procs = [
            AudioProcessInfo(objectID: 143, pid: 1001, bundleID: "com.hnc.Discord.helper.Renderer",
                             executablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/Contents/MacOS/Discord Helper (Renderer)",
                             isRunningOutput: false),
            AudioProcessInfo(objectID: 144, pid: 1002, bundleID: "com.hnc.Discord",
                             executablePath: "/Applications/Discord.app/Contents/MacOS/Discord",
                             isRunningOutput: true),
            AudioProcessInfo(objectID: 145, pid: 1003, bundleID: nil,
                             executablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper (GPU).app/Contents/MacOS/Discord Helper (GPU)",
                             isRunningOutput: false),
            AudioProcessInfo(objectID: 146, pid: 1004, bundleID: "com.hnc.Discord.helper",
                             executablePath: "/Applications/Discord.app/Contents/Frameworks/Discord Helper.app/Contents/MacOS/Discord Helper",
                             isRunningOutput: false),
        ]
        let entries = ProcessCatalog.group(procs)
        #expect(entries.count == 1)
        #expect(entries[0].displayName == "Discord")
        #expect(entries[0].objectIDs == [143, 144, 145, 146])
        #expect(entries[0].isRunningOutput == true)
    }

    @Test func spotifyAndDiscordSortedRunningFirst() {
        let spotify = AudioProcessInfo(objectID: 201, pid: 2001, bundleID: "com.spotify.client",
                                       executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify",
                                       isRunningOutput: true)
        let discord = AudioProcessInfo(objectID: 144, pid: 1002, bundleID: "com.hnc.Discord",
                                       executablePath: "/Applications/Discord.app/Contents/MacOS/Discord",
                                       isRunningOutput: false)
        let entries = ProcessCatalog.group([discord, spotify])
        #expect(entries.count == 2)
        #expect(entries[0].displayName == "Spotify")
        #expect(entries[1].displayName == "Discord")
    }

    @Test func bundleIDsWithoutPaths() {
        let procs = [
            AudioProcessInfo(objectID: 10, pid: 1, bundleID: "com.hnc.Discord", executablePath: nil, isRunningOutput: false),
            AudioProcessInfo(objectID: 11, pid: 2, bundleID: "com.hnc.Discord.helper.GPU", executablePath: nil, isRunningOutput: true),
        ]
        let entries = ProcessCatalog.group(procs)
        #expect(entries.count == 1)
        #expect(entries[0].displayName == "Discord")
        #expect(entries[0].objectIDs == [10, 11])
        #expect(entries[0].isRunningOutput == true)
    }

    @Test func fallbackPID() {
        let procs = [
            AudioProcessInfo(objectID: 50, pid: 4242, bundleID: nil, executablePath: nil, isRunningOutput: false)
        ]
        let entries = ProcessCatalog.group(procs)
        #expect(entries.count == 1)
        #expect(entries[0].displayName == "Process 4242")
        #expect(entries[0].id == "pid:4242")
    }

    @Test func emptyAndShuffled() {
        #expect(ProcessCatalog.group([]).isEmpty)

        let p1 = AudioProcessInfo(objectID: 1, pid: 10, bundleID: "com.apple.Music", executablePath: "/Applications/Music.app/Contents/MacOS/Music", isRunningOutput: false)
        let p2 = AudioProcessInfo(objectID: 2, pid: 20, bundleID: "com.spotify.client", executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify", isRunningOutput: true)
        let g1 = ProcessCatalog.group([p1, p2])
        let g2 = ProcessCatalog.group([p2, p1])
        #expect(g1 == g2)
    }
}
