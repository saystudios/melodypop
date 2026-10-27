import Foundation
import MelodyPopKit
import SwiftData

@Model
final class StudentProfile {
    var id: UUID
    var name: String
    var avatarSymbol: String
    var colorName: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LessonProgress.student)
    var lessonProgress: [LessonProgress] = []
    @Relationship(deleteRule: .cascade, inverse: \PracticeLog.student)
    var practiceLogs: [PracticeLog] = []
    @Relationship(deleteRule: .cascade, inverse: \SavedRecording.student)
    var recordings: [SavedRecording] = []
    @Relationship(deleteRule: .cascade, inverse: \EarnedSticker.student)
    var stickers: [EarnedSticker] = []

    init(name: String, avatarSymbol: String = "music.note", colorName: String = "lavender") {
        id = UUID()
        self.name = name
        self.avatarSymbol = avatarSymbol
        self.colorName = colorName
        createdAt = .now
    }

    func progress(for lessonID: Int) -> LessonProgress? {
        lessonProgress.first { $0.lessonID == lessonID }
    }

    var totalStars: Int { lessonProgress.reduce(0) { $0 + $1.bestStars } }
    var completedLessonIDs: Set<Int> { Set(lessonProgress.filter(\.completed).map(\.lessonID)) }
}

@Model
final class LessonProgress {
    var lessonID: Int
    var bestAccuracy: Double
    var bestStars: Int
    var attempts: Int
    var completed: Bool
    var lastPlayed: Date
    var student: StudentProfile?

    init(lessonID: Int) {
        self.lessonID = lessonID
        bestAccuracy = 0
        bestStars = 0
        attempts = 0
        completed = false
        lastPlayed = .now
    }
}

/// One finished practice activity (lesson, song, game or free play).
@Model
final class PracticeLog {
    var date: Date
    var seconds: Double
    /// "lesson", "song", "game", "freePlay"
    var activity: String
    var itemID: Int
    var itemTitle: String
    var accuracy: Double
    /// Game points (0 for lessons and songs).
    var score: Int = 0
    var inputSource: String
    var student: StudentProfile?

    init(date: Date = .now, seconds: Double, activity: String, itemID: Int, itemTitle: String, accuracy: Double, score: Int = 0, inputSource: InputSource) {
        self.date = date
        self.seconds = seconds
        self.activity = activity
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.accuracy = accuracy
        self.score = score
        self.inputSource = inputSource.rawValue
    }
}

@Model
final class SavedRecording {
    var title: String
    var createdAt: Date
    var duration: Double
    var noteCount: Int
    var data: Data
    var student: StudentProfile?

    init(title: String, recording: PerformanceRecording) throws {
        self.title = title
        createdAt = .now
        duration = recording.duration
        noteCount = recording.noteCount
        data = try recording.encoded()
    }

    var recording: PerformanceRecording? { try? PerformanceRecording.decode(data) }
}

@Model
final class EarnedSticker {
    var stickerID: String
    var earnedAt: Date
    var student: StudentProfile?

    init(stickerID: String) {
        self.stickerID = stickerID
        earnedAt = .now
    }
}

enum DataStore {
    static let schema = Schema([StudentProfile.self, LessonProgress.self, PracticeLog.self, SavedRecording.self, EarnedSticker.self])

    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create the Say Piano data store: \(error)")
        }
    }
}
