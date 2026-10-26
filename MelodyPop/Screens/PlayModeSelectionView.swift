import MelodyPopKit
import SwiftUI

/// Choose how to play: real piano (microphone), MIDI keyboard, or the on-screen piano.
struct PlayModeSelectionView: View {
    @Environment(PlayModeController.self) private var play
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var isFirstRun = false
    @State private var showPairing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    PipMascot(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How will you play?")
                            .font(Theme.font(.title2, weight: .heavy))
                        Text("You can switch any time — even in the middle of a lesson.")
                            .font(Theme.font(.subheadline, weight: .medium))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                }
                ForEach([InputSource.microphone, .midi, .touch]) { source in
                    modeCard(source)
                }
                if isFirstRun {
                    Button("Start learning") {
                        app.needsModeSelection = false
                    }
                    .buttonStyle(PopButtonStyle())
                    .accessibilityIdentifier("start-learning")
                    .padding(.top, 8)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle(isFirstRun ? "" : "Play Mode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPairing) { BluetoothMIDIPairingView() }
    }

    private func modeCard(_ source: InputSource) -> some View {
        let selected = play.mode == source
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await play.select(source) }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: source.symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(source.color, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(Theme.font(.headline, weight: .heavy))
                            Text(source.shortTitle).font(Theme.font(.caption, weight: .bold)).foregroundStyle(source.color)
                        }
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26))
                            .foregroundStyle(selected ? source.color : Theme.inkSoft.opacity(0.4))
                    }
                    Text(description(source))
                        .font(Theme.font(.subheadline, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("select-mode-\(source.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if selected {
                selectedDetails(source)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(selected ? source.color.opacity(0.1) : .white)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(selected ? source.color : .clear, lineWidth: 2))
    }

    private func description(_ s: InputSource) -> String {
        switch s {
        case .microphone:
            return "Put your iPhone or iPad near your acoustic piano. Say Piano listens and checks each note. Best for one note at a time — chord lessons need a keyboard or the screen."
        case .midi:
            return "Connect a digital piano or MIDI keyboard with a USB cable (USB-C or Lightning adapter) or Bluetooth. Every note, chord and the sustain pedal are tracked exactly."
        case .touch:
            return "Play the full 88-key piano right on the screen with as many fingers as you like."
        }
    }

    @ViewBuilder
    private func selectedDetails(_ s: InputSource) -> some View {
        switch s {
        case .microphone:
            if let msg = play.status.message {
                Text(msg).font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.berry)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(play.micMeter.pitch.map { "Hearing \($0.fullName)" } ?? "Play a note to test", systemImage: "waveform")
                        .font(Theme.font(.caption, weight: .bold))
                    Button("Re-measure room noise") { play.mic.recalibrate() }
                        .buttonStyle(PopButtonStyle(color: Theme.peachDeep, compact: true))
                }
            }
        case .midi:
            VStack(alignment: .leading, spacing: 6) {
                if play.midiDevices.isEmpty {
                    Text("No keyboard found yet.").font(Theme.font(.caption, weight: .bold))
                } else {
                    Label(play.midiDevices.joined(separator: ", "), systemImage: "checkmark.circle.fill")
                        .font(Theme.font(.caption, weight: .bold))
                        .foregroundStyle(Theme.mintDeep)
                }
                Button("Pair a Bluetooth keyboard") { showPairing = true }
                    .buttonStyle(PopButtonStyle(color: Theme.mintDeep, compact: true))
            }
        case .touch:
            EmptyView()
        }
    }
}
