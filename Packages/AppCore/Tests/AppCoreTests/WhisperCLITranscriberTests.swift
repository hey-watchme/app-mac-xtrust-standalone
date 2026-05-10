import Foundation
import Testing
@testable import AppCore

struct WhisperCLITranscriberTests {
    @Test
    func makeInvocationIncludesHallucinationSuppressionArguments() {
        let configuration = WhisperCLITranscriberConfiguration(
            executablePath: "/usr/local/bin/whisper",
            modelName: "small",
            language: "ja",
            modelDirectory: "/tmp/models/whisper",
            temperature: 0,
            noSpeechThreshold: 0.72,
            logprobThreshold: -0.4,
            compressionRatioThreshold: 2.0,
            conditionOnPreviousText: false
        )

        let invocation = WhisperCLITranscriber(configuration: configuration).makeInvocation(
            audioFilePath: "/tmp/audio.wav",
            outputDirectory: "/tmp/out"
        )

        #expect(invocation.command == "/usr/local/bin/whisper")
        #expect(argumentValue("--temperature", in: invocation.arguments) == "0.0")
        #expect(argumentValue("--no_speech_threshold", in: invocation.arguments) == "0.72")
        #expect(argumentValue("--logprob_threshold", in: invocation.arguments) == "-0.4")
        #expect(argumentValue("--compression_ratio_threshold", in: invocation.arguments) == "2.0")
        #expect(argumentValue("--condition_on_previous_text", in: invocation.arguments) == "False")
    }

    @Test
    func developmentDefaultDisablesConditioningOnPreviousText() {
        let configuration = WhisperCLITranscriberConfiguration.developmentDefault(
            modelsRootDirectory: "/tmp/models"
        )

        #expect(configuration.temperature == 0)
        #expect(configuration.noSpeechThreshold == 0.6)
        #expect(configuration.logprobThreshold == -1.0)
        #expect(configuration.compressionRatioThreshold == 2.4)
        #expect(configuration.conditionOnPreviousText == false)
    }
}

private func argumentValue(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else {
        return nil
    }

    return arguments[index + 1]
}
