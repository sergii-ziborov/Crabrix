import Foundation

/// Adapters keep cards and lesson exercises on the same signed content source.
extension FlashcardDeck {
    static func cards(from repository: some CourseRepository) -> [Flashcard] {
        var result: [Flashcard] = []
        for course in repository.courses where course.id != "examples" {
            for lesson in course.units.flatMap(\.lessons) {
                guard let writing = repository.writing(for: lesson.id) else { continue }
                let summary = writing.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let rule = writing.rule.trimmingCharacters(in: .whitespacesAndNewlines)
                let explanation = [summary, rule == summary ? "" : rule].filter { !$0.isEmpty }
                let answer = explanation.joined(separator: "\n\n")
                if !answer.isEmpty, answer.utf8.count <= 8_192 {
                    result.append(Flashcard(
                        id: "\(course.id)/\(lesson.id)/concept", courseID: course.id,
                        courseTitle: course.title, lessonID: lesson.id, lessonTitle: lesson.title,
                        kind: .concept, prompt: "What is the core idea of \(lesson.title)?",
                        answer: answer, code: nil
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
