import Foundation

/// The app's author-facing Chinese copy is always presented in simplified Chinese.
///
/// This is intentionally applied at the model boundary as well as when reading
/// older persisted content, so a provider or an earlier saved analysis cannot
/// reintroduce traditional Chinese into the interface.
extension String {
    nonisolated var simplifiedChinese: String {
        applyingTransform(
            StringTransform(rawValue: "Traditional-Simplified"),
            reverse: false
        ) ?? self
    }
}
