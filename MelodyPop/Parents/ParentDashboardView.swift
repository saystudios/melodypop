import Charts
import MelodyPopKit
import SwiftData
import SwiftUI

/// A simple grown-ups-only check before the Parent Dashboard (and purchases).
struct ParentalGateView: View {
    var onPass: () -> Void
    @State private var a = Int.random(in: 6...9)
    @State private var b = Int.random(in: 4...9)
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(Theme.lavenderDeep)
            Text("For grown-ups").font(Theme.font(.title2, weight: .heavy))
            Text("What is \(a) × \(b)?").font(Theme.font(.title3, weight: .bold))
                .accessibilityIdentifier("gate-question")
            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(Theme.font(.title2, weight: .bold))
                .padding(12)
                .frame(maxWidth: 200)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("gate-answer")
            if wrong {
                Text("Not quite — try again.").font(Theme.font(.subheadline, weight: .bold)).foregroundStyle(Theme.berry)
            }
            Button("Continue") {
                if Int(answer) == a * b {
                    onPass()
                } else {
                    wrong = true
                    answer = ""
                    a = Int.random(in: 6...9)
                    b = Int.random(in: 4...9)
                }
            }
            .buttonStyle(PopButtonStyle())
            .accessibilityIdentifier("gate-continue")
        }
        .foregroundStyle(Theme.ink)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

struct ParentAreaView: View {
    @State private var unlocked = false
    var body: some View {
        if unlocked {
            ParentDashboardView()
        } else {
            ParentalGateView { unlocked = true }
                .navigationTitle("Parents")
        }
    }
}

struct ParentDashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayModeController.self) private var play
    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \StudentProfile.createdAt) private var students: [StudentProfile]
    @State private var selectedID: UUID?
    @State private var confirmDelete: StudentProfile?

    private var student: StudentProfile? {
        students.first { $0.id == (selectedID ?? app.currentStudentID) } ?? students.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if students.count > 1 {
                    Picker("Student", selection: Binding(get: { student?.id }, set: { selectedID = $0 })) {
                        ForEach(students) { s in Text(s.name).tag(Optional(s.id)) }
                    }
                    .pickerStyle(.segmented)
                }
                if let s = student {
                    summary(s)
                    practiceChart(s)
                    accuracyChart(s)
                    lessonTable(s)
                    recentActivity(s)
                    profileTools(s)
                }
                settings
                plusCard
            }
            .foregroundStyle(Theme.ink)
            .padding(16)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Parent Dashboard")
        .task { await store.load() }
        .confirmationDialog("Delete \(confirmDelete?.name ?? "")'s profile and all progress?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let s = confirmDelete {
                    context.delete(s)
                    try? context.save()
                    if app.currentStudentID == s.id { app.currentStudentID = nil }
                    selectedID = nil
                }
            }
        }
    }

    // MARK: Sections

    private func weekLogs(_ s: StudentProfile) -> [PracticeLog] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now))!
        return s.practiceLogs.filter { $0.date >= start }
    }

    private func summary(_ s: StudentProfile) -> some View {
        let week = weekLogs(s)
        let minutes = Int((week.reduce(0) { $0 + $1.seconds } / 60).rounded())
        let graded = s.practiceLogs.filter { $0.activity == "lesson" || $0.activity == "song" || $0.activity == "songAttempt" }
        let avg = graded.isEmpty ? nil : graded.map(\.accuracy).reduce(0, +) / Double(graded.count)
        let streak = RewardRules.currentStreak(days: s.practiceLogs.map(\.date))
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                AvatarView(student: s, size: 44)
                Text(s.name).font(Theme.font(.title2, weight: .heavy))
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                tile("\(minutes) min", "Practice this week", "clock.fill", Theme.lavenderDeep)
                tile("\(s.completedLessonIDs.count) / \(Curriculum.lessons.count)", "Lessons complete", "checkmark.seal.fill", Theme.mintDeep)
                tile(avg.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", "Average accuracy", "target", Theme.peachDeep)
                tile("\(streak) days", "Current streak", "flame.fill", Theme.berry)
            }
        }
        .card()
        .accessibilityIdentifier("parent-summary")
    }

    private func tile(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(Theme.font(.title3, weight: .heavy))
            Text(label).font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private struct DayMinutes: Identifiable {
        let day: Date
        let minutes: Double
        var id: Date { day }
    }

    private func practiceChart(_ s: StudentProfile) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days: [DayMinutes] = (0..<14).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            let mins = s.practiceLogs.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.seconds } / 60
            return DayMinutes(day: d, minutes: mins)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Minutes practised (last 14 days)").font(Theme.font(.headline, weight: .heavy))
            Chart(days) { d in
                BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.minutes))
                    .foregroundStyle(Theme.lavenderDeep.gradient)
                    .cornerRadius(4)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 180)
        }
        .card()
    }

    private func accuracyChart(_ s: StudentProfile) -> some View {
        let graded = s.practiceLogs.filter { $0.activity == "lesson" || $0.activity == "song" || $0.activity == "songAttempt" }.sorted { $0.date < $1.date }.suffix(20)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Accuracy, last \(graded.count) attempts").font(Theme.font(.headline, weight: .heavy))
            if graded.isEmpty {
                Text("No lessons or songs played yet.").font(Theme.font(.subheadline)).foregroundStyle(Theme.inkSoft)
            } else {
                Chart(Array(graded.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Attempt", item.offset + 1), y: .value("Accuracy", item.element.accuracy * 100))
                        .foregroundStyle(Theme.mintDeep)
                    PointMark(x: .value("Attempt", item.offset + 1), y: .value("Accuracy", item.element.accuracy * 100))
                        .foregroundStyle(by: .value("Mode", InputSource(rawValue: item.element.inputSource)?.shortTitle ?? "?"))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
            }
        }
        .card()
    }

    private func lessonTable(_ s: StudentProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lessons").font(Theme.font(.headline, weight: .heavy))
            ForEach(Curriculum.units) { unit in
                let lessons = Curriculum.lessons.filter { $0.unit == unit.id }
                let done = lessons.filter { s.progress(for: $0.id)?.completed == true }.count
                HStack {
                    Text("Unit \(unit.id): \(unit.title)").font(Theme.font(.subheadline, weight: .bold))
                    Spacer()
                    ProgressView(value: Double(done), total: Double(lessons.count))
                        .tint(Theme.deep(named: unit.colorName))
                        .frame(width: 100)
                    Text("\(done)/\(lessons.count)").font(Theme.font(.caption, weight: .bold)).monospacedDigit()
                }
            }
            let struggling = s.lessonProgress.filter { $0.attempts >= 3 && !$0.completed }
            if !struggling.isEmpty {
                Text("Needs a little help: " + struggling.compactMap { Curriculum.lesson(id: $0.lessonID)?.title }.joined(separator: ", "))
                    .font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.peachDeep)
            }
        }
        .card()
    }

    private func recentActivity(_ s: StudentProfile) -> some View {
        let recent = s.practiceLogs.sorted { $0.date > $1.date }.prefix(8)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity").font(Theme.font(.headline, weight: .heavy))
            if recent.isEmpty {
                Text("Nothing yet.").font(Theme.font(.subheadline)).foregroundStyle(Theme.inkSoft)
            }
            ForEach(Array(recent), id: \.persistentModelID) { log in
                HStack {
                    Image(systemName: InputSource(rawValue: log.inputSource)?.symbol ?? "music.note").foregroundStyle(Theme.lavenderDeep).frame(width: 22)
                    VStack(alignment: .leading) {
                        Text(log.itemTitle).font(Theme.font(.subheadline, weight: .bold))
                        Text(log.date.formatted(date: .abbreviated, time: .shortened) + " · \(max(1, Int(log.seconds / 60))) min")
                            .font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    if log.activity == "game" {
                        Text("\(log.score) pts").font(Theme.font(.caption, weight: .heavy))
                    } else if log.activity != "freePlay" {
                        Text("\(Int((log.accuracy * 100).rounded()))%").font(Theme.font(.caption, weight: .heavy))
                    }
                }
            }
        }
        .card()
    }

    private func profileTools(_ s: StudentProfile) -> some View {
        HStack {
            Button(role: .destructive) { confirmDelete = s } label: { Label("Delete \(s.name)'s profile", systemImage: "trash") }
            Spacer()
        }
        .font(Theme.font(.subheadline, weight: .bold))
        .card()
    }

    private var settings: some View {
        @Bindable var play = play
        return VStack(alignment: .leading, spacing: 12) {
            Text("Listening (microphone) settings").font(Theme.font(.headline, weight: .heavy))
            Text("Higher sensitivity hears softer playing but may pick up more background noise. Note detection works best one note at a time in a quiet room.")
                .font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
            HStack {
                Text("Sensitivity").font(Theme.font(.subheadline, weight: .bold))
                Slider(value: Binding(get: { 1.7 - play.micSensitivity }, set: { play.micSensitivity = 1.7 - $0 }), in: 0.75...0.95)
            }
        }
        .card()
    }

    private var plusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(Theme.peachDeep)
                Text("Say Piano Plus").font(Theme.font(.headline, weight: .heavy))
                Spacer()
                if store.hasPlus {
                    Label("Unlocked", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.mintDeep).font(Theme.font(.caption, weight: .bold))
                }
            }
            Text("Unlocks lessons 11–30 and every song in the library. One purchase, shared with Family Sharing. No ads, no subscriptions.")
                .font(Theme.font(.subheadline))
            if !store.hasPlus {
                switch store.state {
                case .loading:
                    ProgressView()
                case .unavailable(let msg):
                    Text(msg).font(Theme.font(.caption)).foregroundStyle(Theme.inkSoft)
                case .ready:
                    if let product = store.product {
                        Button("Unlock for \(product.displayPrice)") { Task { await store.purchase() } }
                            .buttonStyle(PopButtonStyle(color: Theme.peachDeep))
                            .accessibilityIdentifier("buy-plus")
                    }
                }
            }
            Button("Restore purchases") { Task { await store.restore() } }
                .font(Theme.font(.subheadline, weight: .bold))
            if let msg = store.purchaseMessage {
                Text(msg).font(Theme.font(.caption, weight: .bold)).foregroundStyle(Theme.lavenderDeep)
            }
        }
        .card(Theme.peachSoft)
    }
}
