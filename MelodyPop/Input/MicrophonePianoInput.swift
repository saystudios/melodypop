import AVFoundation
import MelodyPopKit

/// "Listen to My Piano": acoustic piano detection from the microphone.
///
/// Pipeline: input tap → ring buffer → YIN `PitchTracker` every hop (~21 ms) → `NoteSegmenter`
/// (confidence threshold, calibrated noise gate, stability check) → `NoteEvent`s.
/// Monophonic by design; see `NoteSegmenter` for why note-off and chords can't be inferred reliably.
final class MicrophonePianoInput: PianoInput {
    enum MicError: LocalizedError {
        case permissionDenied, unavailable
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone access is off. Turn it on in Settings › Say Piano to use Listen to My Piano."
            case .unavailable: return "No microphone is available right now."
            }
        }
    }

    struct Meter: Equatable {
        var level: Float = 0
        var pitch: Pitch?
        var confidence: Double = 0
        var calibrating = false
    }

    let source = InputSource.microphone
    var onEvent: ((NoteEvent) -> Void)?
    /// Live readout for the UI (main thread, ~20 Hz).
    var onMeter: ((Meter) -> Void)?
    private(set) var isRunning = false

    /// While true (e.g. the app itself is playing a demo), analysis ignores the input.
    var isSuppressed = false {
        didSet { if isSuppressed { analysisQueue.async { self.segmenter.reset() } } }
    }

    /// Minimum YIN confidence; exposed in Parent settings as "Listening sensitivity".
    var minConfidence: Double = 0.85 {
        didSet { let c = minConfidence; analysisQueue.async { self.segmenter.configuration.minConfidence = c } }
    }

    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "com.saystudios.melodypop.mic", qos: .userInteractive)
    private var tracker: PitchTracker?
    private var segmenter = NoteSegmenter()
    private var calibrator = NoiseCalibrator()
    private var calibrationFrames = 0
    private var ring: [Float] = []
    private var pendingSinceAnalysis = 0
    private let hop = 1024
    private var lastMeterTime: TimeInterval = 0

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw MicError.unavailable }
        let sampleRate = format.sampleRate
        let tracker = PitchTracker(sampleRate: sampleRate)
        analysisQueue.sync {
            self.tracker = tracker
            self.segmenter = NoteSegmenter()
            self.segmenter.configuration.minConfidence = minConfidence
            self.calibrator = NoiseCalibrator()
            self.calibrationFrames = Int(0.8 * sampleRate) / hop // first ~0.8 s measures the room
            self.ring = []
            self.ring.reserveCapacity(tracker.frameLength + 8192)
            self.pendingSinceAnalysis = 0
        }
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(hop), format: format) { [weak self] buffer, when in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: n))
            let startTime = when.isHostTimeValid ? HostClock.seconds(forHostTime: when.hostTime) : HostClock.now - Double(n) / sampleRate
            self.analysisQueue.async { self.process(samples, startTime: startTime, sampleRate: sampleRate) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        analysisQueue.async {
            let events = self.segmenter.finish(at: HostClock.now)
            DispatchQueue.main.async { events.forEach { self.onEvent?($0) } }
        }
    }

    /// Re-measures background noise (e.g. after moving rooms).
    func recalibrate() {
        analysisQueue.async {
            self.calibrator = NoiseCalibrator()
            self.calibrationFrames = 40
        }
    }

    // MARK: Analysis queue

    private func process(_ samples: [Float], startTime: TimeInterval, sampleRate: Double) {
        guard let tracker else { return }
        ring.append(contentsOf: samples)
        let keep = tracker.frameLength
        var events: [NoteEvent] = []
        var lastEstimate: PitchEstimate?
        // Analyze once per hop; timestamps refer to the end of each analysis window.
        var consumed = 0
        pendingSinceAnalysis += samples.count
        while pendingSinceAnalysis >= hop {
            pendingSinceAnalysis -= hop
            consumed = samples.count - pendingSinceAnalysis
            let endIndex = ring.count - pendingSinceAnalysis
            guard endIndex >= keep else { continue }
            let window = Array(ring[(endIndex - keep)..<endIndex])
            let estimate = tracker.analyze(window)
            lastEstimate = estimate
            let windowEnd = startTime + Double(consumed) / sampleRate
            if calibrationFrames > 0 {
                calibrator.add(rms: estimate.rms)
                calibrationFrames -= 1
                if calibrationFrames == 0 { segmenter.configuration.noiseGate = calibrator.recommendedGate }
                continue
            }
            if isSuppressed { continue }
            events += segmenter.process(estimate, at: windowEnd)
        }
        if ring.count > keep + hop * 4 { ring.removeFirst(ring.count - keep - hop) }

        let now = HostClock.now
        let meter: Meter? = (now - lastMeterTime > 0.05 && lastEstimate != nil) ? {
            lastMeterTime = now
            let e = lastEstimate!
            let voiced = e.confidence >= segmenter.configuration.minConfidence && e.rms >= segmenter.configuration.noiseGate
            return Meter(level: Float(min(1, e.rms * 8)), pitch: voiced ? e.nearestPitch : nil, confidence: e.confidence, calibrating: calibrationFrames > 0)
        }() : nil
        guard !events.isEmpty || meter != nil else { return }
        DispatchQueue.main.async {
            events.forEach { self.onEvent?($0) }
            if let meter { self.onMeter?(meter) }
        }
    }
}
