import MelodyPopKit
import SwiftData
import SwiftUI

/// Student profiles, rewards and settings.
struct MeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]
    @State private var showAddProfile = false

    private var student: StudentProfile? {
        students.first { $0.id == app.currentStudentID } ?? students.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profiles
                if let s = student {
                    RewardsSection(student: s)
                }
                links
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Me")
        .sheet(isPresented: $showAddProfile) { AddProfileSheet() }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who's playing?").font(Theme.font(.headline, weight: .heavy))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(students) { s in
                        Button {
                            app.currentStudentID = s.id
                        } label: {
                            VStack(spacing: 6) {
                                AvatarView(student: s, size: 60)
                                    .overlay(Circle().stroke(Theme.lavenderDeep, lineWidth: s.id == student?.id ? 3 : 0))
                                Text(s.name).font(Theme.font(.caption, weight: .bold)).lineLimit(1)
                                StarRow(stars: min(3, s.totalStars / 10), size: 9)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(s.name), \(s.totalStars) stars")
                        .accessibilityAddTraits(s.id == student?.id ? .isSelected : [])
                    }
                    Button {
                        showAddProfile = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .bold))
                                .frame(width: 60, height: 60)
                                .background(Theme.cream, in: Circle())
                                .overlay(Circle().stroke(Theme.lavender, style: StrokeStyle(lineWidth: 2, dash: [5])))
                            Text("Add").font(Theme.font(.caption, weight: .bold))
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add-profile")
                }
            }
        }
        .card()
    }

    private var links: some View {
        VStack(spacing: 0) {
            NavigationLink { PlayModeSelectionView() } label: { linkRow("Play Mode", "pianokeys") }
            Divider()
            NavigationLink { ParentAreaView() } label: { linkRow("Parent Dashboard", "person.2.fill") }
                .accessibilityIdentifier("open-parents")
            Divider()
            NavigationLink { AboutView() } label: { linkRow("About & Credits", "info.circle") }
        }
        .card()
    }

    private func linkRow(_ title: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(Theme.lavenderDeep)
            Text(title).font(Theme.font(.headline))
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
        }
        .foregroundStyle(Theme.ink)
        .padding(.vertical, 10)
    }
}

struct AddProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var avatar = "star.fill"
    @State private var color = "mint"

    var body: some View {
        NavigationStack {
            ScrollView {
                ProfileEditor(name: $name, avatar: $avatar, color: $color)
                    .card()
                    .padding()
            }
            .screenBackground()
            .navigationTitle("New Student")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = StudentProfile(name: name.trimmingCharacters(in: .whitespaces), avatarSymbol: avatar, colorName: color)
                        context.insert(s)
                        try? context.save()
                        app.currentStudentID = s.id
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

struct RewardsSection: View {
    let student: StudentProfile

    var body: some View {
        let earned = Set(student.stickers.map(\.stickerID))
        let snapshot = ProgressService.snapshot(for: student)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Rewards").font(Theme.font(.headline, weight: .heavy))
                Spacer()
                Label("\(RewardRules.currentStreak(days: snapshot.practiceDays)) day streak", systemImage: "flame.fill")
                    .font(Theme.font(.caption, weight: .bold))
                    .foregroundStyle(Theme.peachDeep)
            }
            HStack(spacing: 18) {
                stat("\(student.totalStars)", "stars", "star.fill")
                stat("\(student.completedLessonIDs.count)", "lessons", "checkmark.seal.fill")
                stat("\(earned.count)/\(RewardRules.all.count)", "stickers", "seal.fill")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 14) {
                ForEach(RewardRules.all) { sticker in
                    VStack(spacing: 4) {
                        StickerBadge(sticker: sticker, earned: earned.contains(sticker.id), size: 56)
                        Text(sticker.title).font(Theme.font(.caption2, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
                        Text(sticker.detail).font(Theme.font(.caption2, weight: .regular)).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(sticker.title), \(earned.contains(sticker.id) ? "earned" : "not earned yet"). \(sticker.detail)")
                }
            }
        }
        .card()
        .accessibilityIdentifier("rewards")
    }

    private func stat(_ value: String, _ label: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(Theme.peachDeep)
            Text(value).font(Theme.font(.title3, weight: .heavy))
            Text(label).font(Theme.font(.caption2)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StickerBadge: View {
    let sticker: Sticker
    var earned: Bool
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle()
                .fill(earned ? Theme.accent(named: sticker.colorName) : Theme.creamDeep)
            Circle()
                .stroke(earned ? Theme.deep(named: sticker.colorName) : Theme.inkSoft.opacity(0.2), style: StrokeStyle(lineWidth: 3, dash: earned ? [] : [4]))
                .padding(3)
            Image(systemName: earned ? sticker.symbol : "lock.fill")
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(earned ? Theme.deep(named: sticker.colorName) : Theme.inkSoft.opacity(0.4))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(earned ? -6 : 0))
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    PipMascot(size: 56)
                    VStack(alignment: .leading) {
                        Text("Say Piano").font(Theme.font(.title2, weight: .heavy))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                }
                Text("© Say Studios LLC").font(Theme.font(.subheadline, weight: .bold))
                Text("Questions or feedback: SayStudiosllc@yahoo.com").font(Theme.font(.subheadline))
                Divider()
                Text("Piano sound").font(Theme.font(.headline, weight: .heavy))
                Text("Salamander Grand Piano V3 by Alexander Holm, licensed under Creative Commons Attribution 3.0 (CC BY 3.0). Samples were trimmed, converted to mono and re-encoded for Say Piano.")
                    .font(Theme.font(.subheadline))
                Text("Microphone privacy").font(Theme.font(.headline, weight: .heavy))
                Text("In Listen to My Piano mode, sound from the microphone is analyzed on this device to find the notes you play. Nothing is recorded or sent anywhere.")
                    .font(Theme.font(.subheadline))
                Text("Songs").font(Theme.font(.headline, weight: .heavy))
                Text("All songs in the library are traditional or public-domain melodies, arranged for beginners by Say Studios LLC.")
                    .font(Theme.font(.subheadline))
            }
            .foregroundStyle(Theme.ink)
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .screenBackground()
        .navigationTitle("About")
    }
}
