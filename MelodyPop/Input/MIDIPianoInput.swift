import CoreMIDI
import MelodyPopKit

/// "Connect My Keyboard": any class-compliant USB MIDI keyboard (via USB-C / Lightning adapter)
/// or a Bluetooth LE MIDI keyboard paired with `BluetoothMIDIPairingView`.
/// Connects to every MIDI source and reconnects automatically when devices come and go.
final class MIDIPianoInput: PianoInput {
    enum MIDIError: LocalizedError {
        case clientFailed(OSStatus), portFailed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .clientFailed(let s): return "Couldn't start MIDI (error \(s))."
            case .portFailed(let s): return "Couldn't open a MIDI input (error \(s))."
            }
        }
    }

    let source = InputSource.midi
    var onEvent: ((NoteEvent) -> Void)?
    /// Sustain pedal (CC 64) changes, main thread.
    var onSustain: ((Bool) -> Void)?
    /// Names of connected sources, main thread.
    var onDevicesChanged: (([String]) -> Void)?
    private(set) var isRunning = false
    private(set) var deviceNames: [String] = []

    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: [MIDIEndpointRef] = []
    private var sustainDown = false

    func start() throws {
        guard !isRunning else { return }
        if client == 0 {
            let status = MIDIClientCreateWithBlock("Say Piano" as CFString, &client) { [weak self] notification in
                if notification.pointee.messageID == .msgSetupChanged {
                    DispatchQueue.main.async { self?.connectAllSources() }
                }
            }
            guard status == noErr else { throw MIDIError.clientFailed(status) }
        }
        if port == 0 {
            let status = MIDIInputPortCreateWithProtocol(client, "Say Piano Input" as CFString, ._1_0, &port) { [weak self] eventList, _ in
                self?.receive(eventList)
            }
            guard status == noErr else { throw MIDIError.portFailed(status) }
        }
        isRunning = true
        connectAllSources()
    }

    func stop() {
        for src in connected { MIDIPortDisconnectSource(port, src) }
        connected = []
        isRunning = false
    }

    func connectAllSources() {
        guard isRunning else { return }
        for src in connected { MIDIPortDisconnectSource(port, src) }
        connected = []
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard src != 0 else { continue }
            if MIDIPortConnectSource(port, src, nil) == noErr { connected.append(src) }
            var name: Unmanaged<CFString>?
            if MIDIObjectGetStringProperty(src, kMIDIPropertyDisplayName, &name) == noErr, let n = name?.takeRetainedValue() {
                names.append(n as String)
            } else {
                names.append("MIDI Device \(i + 1)")
            }
        }
        deviceNames = names
        onDevicesChanged?(names)
    }

    /// Core MIDI's receive thread.
    private func receive(_ eventList: UnsafePointer<MIDIEventList>) {
        var events: [NoteEvent] = []
        var sustainChanges: [Bool] = []
        for packet in eventList.unsafeSequence() {
            let count = Int(packet.pointee.wordCount)
            let wordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \.words) ?? 12
            let wordsPtr = UnsafeRawPointer(packet).advanced(by: wordsOffset).assumingMemoryBound(to: UInt32.self)
            let words = Array(UnsafeBufferPointer(start: wordsPtr, count: count))
            let stamp = packet.pointee.timeStamp
            let time = stamp == 0 ? HostClock.now : HostClock.seconds(forHostTime: stamp)
            for message in UMPParser.messages(from: words) {
                switch message {
                case let .noteOn(_, note, velocity) where Pitch.pianoRange.contains(Int(note)):
                    events.append(NoteEvent(kind: .noteOn, pitch: Pitch(Int(note)), velocity: Float(velocity) / 127, time: time, source: .midi))
                case let .noteOff(_, note, _) where Pitch.pianoRange.contains(Int(note)):
                    events.append(NoteEvent(kind: .noteOff, pitch: Pitch(Int(note)), velocity: 0, time: time, source: .midi))
                case let .controlChange(_, controller, value) where controller == MIDIMessage.sustainController:
                    sustainChanges.append(value >= 64)
                default:
                    break
                }
            }
        }
        guard !events.isEmpty || !sustainChanges.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            events.forEach { self.onEvent?($0) }
            for down in sustainChanges where down != self.sustainDown {
                self.sustainDown = down
                self.onSustain?(down)
            }
        }
    }
}
