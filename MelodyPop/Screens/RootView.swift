import MelodyPopKit
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]
    @State private var started = false

    var body: some View {
        Group {
            if students.isEmpty {
                OnboardingView()
            } else if app.needsModeSelection {
                NavigationStack {
                    PlayModeSelectionView(isFirstRun: true)
                }
            } else {
                MainTabView()
            }
        }
        .task {
            guard !started else { return }
            started = true
            app.seedForUITests(context: context)
            await app.play.activateCurrentMode()
            await app.store.load()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            JourneyView()
                .tabItem { Label("Journey", systemImage: "map.fill") }
                .accessibilityIdentifier("tab-journey")
            NavigationStack { FreePlayView() }
                .tabItem { Label("Piano", systemImage: "pianokeys") }
                .accessibilityIdentifier("tab-piano")
            SongLibraryView()
                .tabItem { Label("Songs", systemImage: "music.note.list") }
                .accessibilityIdentifier("tab-songs")
            NavigationStack { GamesHubView() }
                .tabItem { Label("Games", systemImage: "gamecontroller.fill") }
                .accessibilityIdentifier("tab-games")
            NavigationStack { MeView() }
                .tabItem { Label("Me", systemImage: "person.crop.circle.fill") }
        }
    }
}

/// First launch: create a student profile.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var avatar = "music.note"
    @State private var color = "lavender"

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                PipMascot(size: 110, mood: .cheering)
                    .padding(.top, 40)
                Text("Welcome to Say Piano!")
                    .font(Theme.font(.largeTitle, weight: .heavy))
                    .multilineTextAlignment(.center)
                Text("Who's learning piano today?")
                    .font(Theme.font(.title3, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                ProfileEditor(name: $name, avatar: $avatar, color: $color)
                    .card()
                Button("Let's play!") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let s = StudentProfile(name: trimmed, avatarSymbol: avatar, colorName: color)
                    context.insert(s)
                    try? context.save()
                    app.currentStudentID = s.id
                }
                .buttonStyle(PopButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("create-profile")
            }
            .foregroundStyle(Theme.ink)
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
    }
}

struct ProfileEditor: View {
    @Binding var name: String
    @Binding var avatar: String
    @Binding var color: String

    static let avatars = ["music.note", "star.fill", "heart.fill", "moon.stars.fill", "leaf.fill", "pawprint.fill", "sun.max.fill", "cloud.fill"]
    static let colors = ["lavender", "mint", "peach"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Name").font(Theme.font(.headline))
            TextField("First name", text: $name)
                .textContentType(.givenName)
                .font(Theme.font(.title3))
                .padding(12)
                .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("profile-name")
            Text("Pick a picture").font(Theme.font(.headline))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(Self.avatars, id: \.self) { a in
                    Button {
                        avatar = a
                    } label: {
                        Image(systemName: a)
                            .font(.system(size: 24, weight: .bold))
                            .frame(width: 54, height: 54)
                            .background(avatar == a ? Theme.accent(named: color) : Theme.cream, in: Circle())
                            .foregroundStyle(Theme.deep(named: color))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(avatar == a ? .isSelected : [])
                }
            }
            Text("Favourite colour").font(Theme.font(.headline))
            HStack(spacing: 14) {
                ForEach(Self.colors, id: \.self) { c in
                    Button {
                        color = c
                    } label: {
                        Circle().fill(Theme.accent(named: c))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Theme.ink, lineWidth: color == c ? 3 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.capitalized)
                }
            }
        }
    }
}

struct AvatarView: View {
    let student: StudentProfile
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: student.avatarSymbol)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(Theme.deep(named: student.colorName))
            .frame(width: size, height: size)
            .background(Theme.accent(named: student.colorName), in: Circle())
            .accessibilityHidden(true)
    }
}
