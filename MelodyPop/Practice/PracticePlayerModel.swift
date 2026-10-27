import Foundation
import MelodyPopKit
import Observation

/// Drives one practice run of a `PracticeItem` with the shared `PracticeSession` engine.
/// Input arrives from `PlayModeController` regardless of play mode, so switching modes only
/// pauses and resumes — progress and score are kept.
@Observable
@MainActor
final class PracticePlayerModel {
    enum Phase: Equatable {
        case ready
        case countIn(beatsLeft: Int)
        case playing
        case paused(String?)
        case demo
        case finished
    }

    let item: PracticeItem
    private(set) var session: PracticeSession
    private(set) var phase: Phase = .ready
    private(set) var now: TimeInterval = HostClock.now
    private(set) var feedback: Grade?
    private(set) var feedbackID = 0
    private(set) var result: SessionResult?
    /// Bumped whenever the (non-observable) session changes so views refresh.
    private(set) var revision = 0
    private(set) var practiceSeconds: TimeInterval = 0

    var tempoScale: Double = 1 {
        didSet { session.setTempoScale(tempoScale, at: HostClock.now); revision += 1 }
    }
    var metronomeOn = true

    @ObservationIgnored var onFinished: ((SessionResult, TimeInterval, InputSource) -> Void)?
    @ObservationIgnored private weak var play: PlayModeController?
    @ObservationIgnored private var listenerID: UUID?
    @ObservationIgnored private var ticker: FrameTicker?
    @ObservationIgnored private var countInEnd: TimeInterval = 0
    @ObservationIgnored private var lastClickBeat = Int.min
    @ObservationIgnored private var playingSince: TimeInterval?
    @ObservationIgnored private var demoCursor: [(time: TimeInterval, on: Bool, midi: Int)] = []
    @ObservationIgnored private var demoIndex = 0
    @ObservationIgnored private var resumeAfterDemo = false

    init(item: PracticeItem, source: InputSource) {
        self.item = item
        session = PracticeSession(piece: item.piece, mode: item.mode, capabilities: source.capabilities)
    }

    var isTimed: Bool { item.mode == .timed }
    var currentBeat: Double { isTimed && (session.isRunning || session.isFinished) ? session.beat(at: now) : 0 }

    // MARK: Wiring

    func attach(to play: PlayModeController) {
        self.play = play
        session.setCapabilities(play.mode.capabilities)
        if listenerID == nil {
            listenerID = play.addListener { [weak self] event in MainActor.assumeIsolated { self?.handle(event) } }
        }
        ensureTicking()
    }

    /// The frame ticker drives count-ins, timed scoring and demos. It is (re)started whenever
    /// something needs it, so a view disappearing and reappearing can never leave a run frozen.
    private func ensureTicking() {
        if ticker == nil {
            ticker = FrameTicker { [weak self] in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        ticker?.start()
    }

    func detach() {
        if let id = listenerID { play?.removeListener(id) }
        listenerID = nil
        ticker?.stop()
        stopDemo()
        accumulateTime()
    }

    // MARK: Control

    func start() {
        guard let play else { return }
        if let reason = item.unavailableReason(for: play.mode) {
            phase = .paused(reason)
            return
        }
        feedback = nil
        ensureTicking()
        let t = HostClock.now
        if isTimed {
            let beats = item.piece.beatsPerBar
            countInEnd = t + Double(beats) * session.secondsPerBeat
            session.start(at: countInEnd)
            lastClickBeat = -beats - 1
            phase = .countIn(beatsLeft: beats)
        } else {
            session.start(at: t)
            phase = .playing
        }
        playingSince = t
        revision += 1
    }

    func retry() {
        accumulateTime()
        session = PracticeSession(piece: item.piece, mode: item.mode, capabilities: (play?.mode ?? .touch).capabilities, tempoScale: tempoScale)
        result = nil
        feedback = nil
        phase = .ready
        revision += 1
        start()
    }

    func togglePause() {
        switch phase {
        case .playing, .countIn: pause(reason: nil)
        case .paused: resume()
        default: break
        }
    }

    func pause(reason: String?) {
        let t = HostClock.now
        if session.isRunning { session.pause(at: t) }
        accumulateTime()
        phase = .paused(reason)
        revision += 1
    }

    /// Resumes after a pause or a mode switch. Timed pieces get a one-bar count-in first.
    func resume() {
        guard let play else { return }
        if let reason = item.unavailableReason(for: play.mode) {
            phase = .paused(reason)
            return
        }
        if let msg = play.status.message {
            phase = .paused(msg)
            return
        }
        guard session.isRunning || session.isPaused else { start(); return }
        ensureTicking()
        let t = HostClock.now
        playingSince = t
        if isTimed {
            let beats = item.piece.beatsPerBar
            countInEnd = t + Double(beats) * session.secondsPerBeat
            // Paused during the count-in: start the count-in over so beat 0 lands right after it.
            let pausedBeat = session.beat(at: t)
            session.resume(at: pausedBeat < 0 ? countInEnd + pausedBeat * session.secondsPerBeat : countInEnd)
            lastClickBeat = Int(floor(session.beat(at: t))) - 1
            phase = .countIn(beatsLeft: beats)
        } else {
            session.resume(at: t)
            phase = .playing
        }
        revision += 1
    }

    /// Called right before the play mode changes.
    func modeWillChange() {
        if case .playing = phase { pause(reason: nil) }
        if case .countIn = phase { pause(reason: nil) }
    }

    /// Called once the new mode is active (or failed).
    func modeDidChange(to source: InputSource) {
        session.setCapabilities(source.capabilities)
        revision += 1
        if case .paused = phase {
            if let reason = item.unavailableReason(for: source) {
                phase = .paused(reason)
            } else if let msg = play?.status.message {
                phase = .paused(msg)
            } else if session.isPaused {
                resume()
            } else {
                phase = .paused(nil)
            }
        }
    }

    // MARK: Events

    private func handle(_ event: NoteEvent) {
        guard event.kind == .noteOn else { return }
        switch phase {
        case .playing, .countIn: break
        default: return
        }
        // Ignore notes well before the first beat (kids warming up during the count-in).
        if isTimed && session.beat(at: event.compensatedTime) < -0.5 { return }
        let doneBefore = session.completedCount
        session.handle(event)
        noteProgress(doneBefore: doneBefore)
        revision += 1
        if session.isFinished { finish() }
    }

    private func noteProgress(doneBefore: Int) {
        guard session.completedCount > doneBefore else { return }
        let latest = session.targets.filter { $0.status == .done }.max(by: { $0.note.startBeat < $1.note.startBeat })
        if let g = latest?.grade {
            feedback = g
            feedbackID += 1
        }
    }

    private func tick() {
        now = HostClock.now
        if phase == .demo { stepDemo(); return }
        guard isTimed else { return }
        switch phase {
        case .countIn:
            let left = Int(ceil((countInEnd - now) / session.secondsPerBeat))
            if left <= 0 { phase = .playing } else if case .countIn(let current) = phase, current != left { phase = .countIn(beatsLeft: left) }
            clickIfNeeded()
        case .playing:
            clickIfNeeded()
            let doneBefore = session.completedCount
            session.tick(at: now)
            noteProgress(doneBefore: doneBefore)
            if session.isFinished { finish() }
        default:
            break
        }
    }

    private func clickIfNeeded() {
        guard metronomeOn, let play, play.mode != .microphone else { return } // clicks would confuse pitch detection
        let beat = Int(floor(session.beat(at: now) + 0.001))
        if beat > lastClickBeat {
            lastClickBeat = beat
            let bar = item.piece.beatsPerBar
            PianoAudioEngine.shared.click(accent: ((beat % bar) + bar) % bar == 0)
        }
    }

    private func finish() {
        accumulateTime()
        let r = session.result
        result = r
        phase = .finished
        revision += 1
        onFinished?(r, practiceSeconds, play?.mode ?? .touch)
        practiceSeconds = 0
    }

    private func accumulateTime() {
        if let since = playingSince {
            practiceSeconds += HostClock.now - since
            playingSince = nil
        }
    }

    // MARK: Hints

    var hintedKeys: Set<Int> {
        _ = revision
        switch phase {
        case .playing, .countIn, .paused:
            return session.upcomingPitches(at: isTimed ? now : HostClock.now)
        case .demo:
            return []
        default:
            return Set(item.piece.notes.first?.pitches.map(\.midi) ?? [])
        }
    }

    // MARK: Demo ("Listen")

    func playDemo() {
        guard phase != .demo else { stopDemo(); return }
        resumeAfterDemo = false
        if case .playing = phase { pause(reason: nil); resumeAfterDemo = true }
        let spb = 60 / (item.piece.tempo * tempoScale)
        let t0 = HostClock.now + 0.3
        var events: [(TimeInterval, Bool, Int)] = []
        for n in item.piece.notes {
            for p in n.pitches {
                events.append((t0 + n.startBeat * spb, true, p.midi))
                events.append((t0 + (n.startBeat + n.beats * 0.92) * spb, false, p.midi))
            }
        }
        demoCursor = events.sorted { $0.0 < $1.0 }.map { (time: $0.0, on: $0.1, midi: $0.2) }
        demoIndex = 0
        ensureTicking()
        play?.setAppPlaying(true)
        phase = .demo
    }

    private func stepDemo() {
        while demoIndex < demoCursor.count && demoCursor[demoIndex].time <= now {
            let e = demoCursor[demoIndex]
            if e.on { PianoAudioEngine.shared.noteOn(e.midi, velocity: 0.7) } else { PianoAudioEngine.shared.noteOff(e.midi) }
            demoIndex += 1
        }
        if demoIndex >= demoCursor.count { stopDemo() }
    }

    var demoBeat: Double? {
        guard phase == .demo, let first = demoCursor.first else { return nil }
        return (now - first.time) / (60 / (item.piece.tempo * tempoScale))
    }

    func stopDemo() {
        guard phase == .demo else { return }
        for e in demoCursor where e.on { PianoAudioEngine.shared.noteOff(e.midi) }
        demoCursor = []
        // Give the piano's ring a moment to fade before the microphone listens again.
        let play = self.play
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { play?.setAppPlaying(false) }
        if session.isPaused {
            phase = .paused(nil)
            if resumeAfterDemo { resume() }
        } else {
            phase = .ready
        }
    }
}
