import Foundation

/// Adapters keep cards and lesson exercises on the same signed content source.
extension FlashcardDeck {
    static func cards(from repository: some CourseRepository) -> [Flashcard] {
        var result: [Flashcard] = []
        for course in repository.courses where course.id != "examples" {
            for lesson in course.units.flatMap(\.lessons) {
                guard let writing = repository.writing(for: lesson.id) else { continue }
                // Authored recall questions about the lesson. A lesson without
                // them keeps only its Quick Check card below.
                for (index, recall) in writing.recall.enumerated() {
                    let code = recall.code?.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard recall.answer.utf8.count <= 8_192, (code?.utf8.count ?? 0) <= 8_192,
                          (code?.split(separator: "\n").count ?? 0) <= 80 else { continue }
                    result.append(Flashcard(
                        id: "\(course.id)/\(lesson.id)/recall-\(index)", courseID: course.id,
                        courseTitle: course.title, lessonID: lesson.id, lessonTitle: lesson.title,
                        kind: .concept, prompt: recall.question.trimmingCharacters(in: .whitespacesAndNewlines),
                        answer: recall.answer.trimmingCharacters(in: .whitespacesAndNewlines),
                        code: code?.isEmpty == false ? code : nil
                    ))
                }
                // The same authored prompt/answer powers the lesson question.
                // Never show a context-dependent question with silently cut code.
                let context = writing.practiceCode.trimmingCharacters(in: .whitespacesAndNewlines)
                if writing.answers.indices.contains(writing.correctAnswer),
                   !writing.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   context.utf8.count <= 8_192, context.split(separator: "\n").count <= 80 {
                    let correct = writing.answers[writing.correctAnswer]
                    let feedback = writing.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                    let answer = feedback.isEmpty || feedback == correct ? correct : correct + "\n\n" + feedback
                    result.append(Flashcard(
                        id: "\(course.id)/\(lesson.id)/question", courseID: course.id,
                        courseTitle: course.title, lessonID: lesson.id, lessonTitle: lesson.title,
                        kind: .question, prompt: writing.question, answer: answer,
                        code: context.isEmpty ? nil : context
                    ))
                }
            }
        }
        return Array(result.prefix(maximumCards))
    }
}
