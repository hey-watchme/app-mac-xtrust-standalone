import Foundation
import Speech

struct SpeechAssetStatus: Equatable, Sendable {
    let localeIdentifier: String
    let localeSupported: Bool
    let localeInstalled: Bool
}

enum SpeechAssetStatusProvider {
    static func status(localeIdentifier: String = "ja-JP") async -> SpeechAssetStatus {
        let target = Locale(identifier: localeIdentifier)
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: target) != nil
        let installed = await SpeechTranscriber.installedLocales.contains {
            $0.identifier(.bcp47) == target.identifier(.bcp47)
        }
        return SpeechAssetStatus(
            localeIdentifier: localeIdentifier,
            localeSupported: supported,
            localeInstalled: installed
        )
    }
}
