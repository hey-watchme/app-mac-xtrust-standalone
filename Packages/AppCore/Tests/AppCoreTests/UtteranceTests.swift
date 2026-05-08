import Foundation
import Testing
@testable import AppCore

struct UtteranceTests {
    @Test
    func transitionsTranscriptionLifecycle() {
        let topicID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let utterance = Utterance(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
            topicID: topicID,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_004),
            durationSeconds: 4,
            audioFilePath: "/tmp/test.wav"
        )

        let running = utterance.transcriptionStarted()
        let completed = running.transcriptionCompleted(
            transcriptText: "こんにちは",
            transcriptFilePath: "/tmp/test.txt",
            durationSeconds: 1.5
        )

        #expect(running.transcriptionStatus == .running)
        #expect(completed.transcriptionStatus == .completed)
        #expect(completed.transcriptText == "こんにちは")
        #expect(completed.transcriptFilePath == "/tmp/test.txt")
        #expect(completed.topicID == topicID)
    }
}
