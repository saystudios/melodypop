import MelodyPopKit
import SwiftData
import SwiftUI

/// The learning journey: units of lessons along a winding path.
struct JourneyView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayModeController.self) private var play
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]
    @State private var path: [Int] = []
    @State private var lockedMessage: String?

    private var student: StudentProfile? {
        students.first { $0.id == app.currentStudentID } ?? students.first
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    ForEach(Curriculum.units) { unit in
                        unitSection(unit)
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle("Learning Journey")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { id in
                if let lesson = Curriculum.lesson(id: id) {
                    PracticePlayerView(
                        item: PracticeItem(lesson: lesson),
                        source: play.mode,
                        nextItem: Curriculum.lesson(id: id + 1).flatMap { next in
                            isUnlocked(next.id, afterCompleting: id) && !Entitlements.isLessonLocked(next.id, hasPlus: store.hasPlus) ? PracticeItem(lesson: next) : nil
                        },
                        onNext: { next in path = [next.id] }
                    )
                    .id(id)
                }
            }
            .alert("Not yet!", isPresented: Binding(get: { lockedMessage != nil }, set: { if !$0 { lockedMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lockedMessage ?? "")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let s = student { AvatarView(student: s, size: 52) }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hi, \(student?.name ?? "friend")!")
                    .font(Theme.font(.title2, weight: .heavy))
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.peachDeep)
                    Text("\(student?.totalStars ?? 0) stars").font(Theme.font(.subheadline, weight: .bold))
                }
            }
            Spacer()
            NavigationLink {
                PlayModeSelectionView()
            } label: {
                Label(play.mode.shortTitle, systemImage: play.mode.symbol)
                    .font(Theme.font(.caption, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(play.mode.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(play.mode.color)
            }
            .accessibilityIdentifier("open-play-mode")
        }
        .foregroundStyle(Theme.ink)
        .card()
    }

    private func unitSection(_ unit: CurriculumUnit) -> some View {
        let lessons = Curriculum.lessons.filter { $0.unit == unit.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Unit \(unit.id)").font(Theme.font(.caption, weight: .heavy)).foregroundStyle(Theme.deep(named: unit.colorName))
                Text(unit.title).font(Theme.font(.title3, weight: .heavy))
            }
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                lessonRow(lesson, wiggle: index)
            }
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(Theme.accent(named: unit.colorName).opacity(0.18))
    }

    private func lessonRow(_ lesson: Lesson, wiggle: Int) -> some View {
        let progress = student?.progress(for: lesson.id)
        let premiumLocked = Entitlements.isLessonLocked(lesson.id, hasPlus: store.hasPlus)
        let unlocked = isUnlocked(lesson.id) && !premiumLocked
        let offsets: [CGFloat] = [0, 34, 60, 34, 0, -20]
        return Button {
            if unlocked {
                path.append(lesson.id)
            } else if premiumLocked && isUnlocked(lesson.id) {
                lockedMessage = "\"\(lesson.title)\" is part of Say Piano Plus. Ask a grown-up to look in the Parent Dashboard (Me tab)."
            } else {
                lockedMessage = "Finish lesson \(lesson.id - 1) to unlock \"\(lesson.title)\"."
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(progress?.completed == true ? Theme.mint : unlocked ? Theme.lavender : Theme.creamDeep)
                        .frame(width: 56, height: 56)
                        .shadow(color: Theme.lavenderDeep.opacity(unlocked ? 0.25 : 0), radius: 6, y: 3)
                    if unlocked {
                        Image(systemName: progress?.completed == true ? "checkmark" : lesson.kind.symbol)
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(progress?.completed == true ? Theme.mintDeep : .white)
                    } else {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.inkSoft)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(lesson.id). \(lesson.title)").font(Theme.font(.headline, weight: .bold))
                    Text(lesson.goal).font(Theme.font(.caption, weight: .medium)).foregroundStyle(Theme.inkSoft).lineLimit(2)
                    HStack(spacing: 6) {
                        StarRow(stars: progress?.bestStars ?? 0, size: 11)
                        Text(lesson.kind.label).font(Theme.font(.caption2, weight: .bold)).foregroundStyle(Theme.lavenderDeep)
                        if lesson.requiresPolyphony {
                            Image(systemName: "mic.slash").font(.caption2).foregroundStyle(Theme.inkSoft)
                                .accessibilityLabel("Needs keyboard or screen")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, offsets[wiggle % offsets.count])
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lesson-\(lesson.id)")
    }

    private func isUnlocked(_ id: Int, afterCompleting justCompleted: Int? = nil) -> Bool {
        if id == 1 { return true }
        if justCompleted == id - 1 { return true }
        return student?.progress(for: id - 1)?.completed == true
    }
}
