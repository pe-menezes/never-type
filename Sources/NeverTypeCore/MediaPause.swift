import AppKit
import CoreAudio
import Foundation

/// Pauses whatever is playing when a recording starts, and plays it again when
/// the recording ends, but only if this type is the one that paused it.
///
/// Two halves of macOS answer two different questions, and neither answers
/// both. Measured on macOS 27.0 (26A428), 2026-10-02, with Spotify playing:
///
/// - MediaRemote's `MRMediaRemoteSendCommand` still works from an app without
///   Apple's entitlement: pause stopped Spotify, play brought it back, 3 of 3.
/// - MediaRemote's "is anything playing" (`GetNowPlayingApplicationIsPlaying`)
///   does not: it answered `false` with Spotify playing, every time. Locked
///   since macOS 15.4 for apps outside Apple's list.
/// - CoreAudio's per-process `kAudioProcessPropertyIsRunningOutput` (public,
///   macOS 14.2+) does see it, and is what this type reads.
///
/// Why "is anything playing" matters at all: play is the dangerous half. A play
/// sent with nothing paused starts the last player there was, and music
/// starting out of nowhere when you finish dictating is worse than music that
/// kept playing. So nothing is sent when no app is putting out sound, and play
/// goes out only once an app that was playing has gone quiet. A call in Zoom
/// keeps putting out sound through the pause, so it never gets a play.
///
/// The cost is the delay of the quiet. Spotify releases the output 2294 to
/// 2338 ms after the pause (3 runs), and comes back 42 to 48 ms after play. A
/// dictation shorter than that waits for the quiet before the music returns.
@MainActor
public final class MediaPause {

    /// The two MediaRemote commands this type sends. The raw values are
    /// MediaRemote's own (`kMRPlay`, `kMRPause`). Explicit pause, never the
    /// toggle: a toggle sent into silence would start the music.
    public enum Command: UInt32, Sendable {
        case play = 0
        case pause = 1
    }

    /// What `recordingStarted()` did, for the log line.
    public enum Start: Equatable, Sendable {
        /// No app was putting out sound. Nothing was sent.
        case nothingPlaying
        /// Pause sent while these apps were playing.
        case paused(Set<pid_t>)
        /// The previous recording's pause is still waiting to be undone, and
        /// this recording keeps it.
        case keptPaused
        /// MediaRemote refused or is gone. Nothing will be resumed.
        case commandFailed
    }

    /// What `recordingEnded()` did, for the log line.
    public enum End: Equatable, Sendable {
        /// Nothing was paused by this type.
        case nothingToResume
        /// An app that was playing went quiet, and play was sent.
        case resumed
        /// These apps never went quiet: the pause did not reach them, so play
        /// would only start something nobody had playing.
        case stillPlaying(Set<pid_t>)
        /// A new recording started while this one waited for the quiet.
        case superseded
        /// Play was refused.
        case commandFailed
    }

    private let playingApps: @MainActor () -> Set<pid_t>
    private let send: @MainActor (Command) -> Bool
    private let now: () -> ContinuousClock.Instant
    private let sleep: @MainActor (Duration) async -> Void
    private let settle: Duration
    private let poll: Duration

    /// The apps that were playing when pause went out, and when it went out.
    private var paused: (apps: Set<pid_t>, at: ContinuousClock.Instant)?
    /// Bumped by every start and every end, so a wait for the quiet that a
    /// new recording overtook gives up instead of sending play mid-recording.
    private var generation = 0

    /// - Parameters:
    ///   - settle: how long after the pause an app still playing counts as one
    ///     the pause did not reach. 3.5 s against Spotify's measured ~2.3 s.
    ///   - poll: how often the output is read while waiting.
    public init(playingApps: @escaping @MainActor () -> Set<pid_t> = MediaPause.playingApps,
                send: @escaping @MainActor (Command) -> Bool = MediaPause.sendMediaRemote,
                now: @escaping () -> ContinuousClock.Instant = { .now },
                sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                settle: Duration = .milliseconds(3500),
                poll: Duration = .milliseconds(50)) {
        self.playingApps = playingApps
        self.send = send
        self.now = now
        self.sleep = sleep
        self.settle = settle
        self.poll = poll
    }

    /// Call before the start tone. The tone comes from this process, which
    /// `playingApps` leaves out, so the order is not load-bearing, but the
    /// reading is cleaner without it.
    public func recordingStarted() -> Start {
        generation += 1
        if paused != nil { return .keptPaused }
        let apps = playingApps()
        guard !apps.isEmpty else { return .nothingPlaying }
        guard send(.pause) else { return .commandFailed }
        paused = (apps, now())
        return .paused(apps)
    }

    /// Call when the recording ends, kept or discarded. Returns once play was
    /// sent or given up on, at most `settle` after the pause.
    public func recordingEnded() async -> End {
        guard let watched = paused else { return .nothingToResume }
        generation += 1
        let mine = generation
        while true {
            let still = playingApps().intersection(watched.apps)
            // Any one of them going quiet is the pause landing. Waiting for all
            // would wait out a Zoom call that was playing beside the music.
            if still.count < watched.apps.count {
                paused = nil
                return send(.play) ? .resumed : .commandFailed
            }
            if now() - watched.at >= settle {
                paused = nil
                return .stillPlaying(still)
            }
            await sleep(poll)
            guard generation == mine else { return .superseded }
        }
    }

    // MARK: - The first value

    /// The switch's first value on this Mac, decided at the first launch of a
    /// build that has it and stored either way.
    ///
    /// A new install starts with the pause on. An install that ran before the
    /// switch existed starts with it off. Whoever already dictates with
    /// NeverType is used to the music going on under the voice, and some call
    /// that a quality. An update that started pausing it would break a habit
    /// nobody asked to change. Whoever installs now has no habit to break.
    /// `ranBefore` is whether the log of an earlier launch was there when this
    /// one started (`startLog` in `main.swift`).
    ///
    /// - Returns: the value to store, or nil when one is already stored. A
    ///   stored value is the person's, or this rule's from an earlier launch,
    ///   and neither is overwritten.
    nonisolated public static func firstValue(stored: Bool?, ranBefore: Bool) -> Bool? {
        guard stored == nil else { return nil }
        return !ranBefore
    }

    // MARK: - System

    /// Regular apps putting out sound right now, this process excluded.
    ///
    /// Regular apps only (the ones with a Dock tile): a notification sound
    /// comes from a system process and ends by itself, and seeing it end would
    /// pass for the pause landing and send play to a player nobody had on.
    public static func playingApps() -> Set<pid_t> {
        let own = ProcessInfo.processInfo.processIdentifier
        var result = Set<pid_t>()
        for process in audioProcesses() {
            var running: UInt32 = 0
            guard read(process, kAudioProcessPropertyIsRunningOutput, &running) == noErr,
                  running != 0 else { continue }
            var pid: pid_t = 0
            guard read(process, kAudioProcessPropertyPID, &pid) == noErr, pid != own,
                  NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            else { continue }
            result.insert(pid)
        }
        return result
    }

    private static func audioProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID,
                                                 _ selector: AudioObjectPropertySelector,
                                                 _ value: inout T) -> OSStatus {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    /// Resolved once. A private framework, so a missing symbol is a case this
    /// code has to handle, not a crash: it comes back nil, and every command
    /// then answers `false` and says so in the log.
    private static let sendCommand: SendCommand? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                                  RTLD_NOW),
              let symbol = dlsym(handle, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()

    /// Sends the command to whichever app macOS has as the player in front.
    public static func sendMediaRemote(_ command: Command) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}
