import MelodyPopKit
import SwiftData
import SwiftUI

extension PracticeItem {
    init(song: Song) {
        self.init(kind: .song, id: song.id, title: song.title, subtitle: song.origin,
                  tip: "Use the speed menu to practise slowly first. Tap Listen to hear how it goes.",
                  piece: song.piece, mode: .timed, passAccuracy: 0.75)
    }
}

/// Song Library → Song Practice (sheet music, highlighted keys, tempo, retry, scoring).
struct SongLibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayModeController.self) private var play
    @Environment(StoreManager.self) private var store
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]
    @State private var level: Int = 0
    @State private var path: [Int] = []
    @State private var lockedSong: Song?

    private var student: StudentProfile? { students.first { $0.id == app.currentStudentID } ?? students.first }

    private func bestAccuracy(_ song: Song) -> Double? {
        student?.practiceLogs.filter { ($0.activity == "song" || $0.activity == "songAttempt") && $0.itemID == song.id }.map(\.accuracy).max()
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Level", selection: $level) {
                        Text("All").tag(0)
                        Text("Easy").tag(1)
                        Text("Medium").tag(2)
                        Text("Tricky").tag(3)
                    }
                    .pickerStyle(.segmented)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(SongLibrary.songs.filter { level == 0 || $0.level == level }) { song in
                            songCard(song)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle("Song Library")
            .navigationDestination(for: Int.self) { id in
                if let song = SongLibrary.song(id: id) {
                    PracticePlayerView(item: PracticeItem(song: song), source: play.mode)
                        .id(id)
                }
            }
            .alert("Say Piano Plus", isPresented: Binding(get: { lockedSong != nil }, set: { if !$0 { lockedSong = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\"\(lockedSong?.title ?? "")\" is part of Say Piano Plus. Ask a grown-up to look in the Parent Dashboard.")
            }
        }
    }

    private func songCard(_ song: Song) -> some View {
        let locked = Entitlements.isSongLocked(song, hasPlus: store.hasPlus)
        let best = bestAccuracy(song)
        return Button {
            if locked { lockedSong = song } else { path.append(song.id) }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill([Theme.lavender, Theme.mint, Theme.peach][song.id % 3])
                        .frame(width: 58, height: 58)
                    Image(systemName: locked ? "lock.fill" : song.requiresPolyphony ? "music.quarternote.3" : "music.note")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).font(Theme.font(.headline, weight: .heavy)).multilineTextAlignment(.leading)
                    Text(song.origin).font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(i < song.level ? Theme.lavenderDeep : Theme.lavenderSoft).frame(width: 7, height: 7)
                        }
                        Text("\(Int(song.piece.tempo)) bpm").font(Theme.font(.caption2, weight: .bold)).foregroundStyle(Theme.inkSoft)
                        if song.requiresPolyphony {
                            Text("Two hands").font(Theme.font(.caption2, weight: .bold)).foregroundStyle(Theme.mintDeep)
                        }
                    }
                }
                Spacer(minLength: 0)
                if let best {
                    VStack(spacing: 2) {
                        StarRow(stars: SessionResult.stars(for: best), size: 10)
                        Text("\(Int((best * 100).rounded()))%").font(Theme.font(.caption, weight: .heavy)).foregroundStyle(Theme.lavenderDeep)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("song-\(song.id)")
    }
}
