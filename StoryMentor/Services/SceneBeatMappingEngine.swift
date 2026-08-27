import Foundation

@MainActor
enum SceneBeatMappingEngine {
    static func confirm(
        _ option: SceneBeatChoiceOption,
        in microBeatID: UUID,
        contract: SceneContract,
        project: StoryProject
    ) throws {
        var microBeats = contract.microBeats
        guard let microBeatIndex = microBeats.firstIndex(where: { $0.id == microBeatID }) else {
            throw SceneBeatMappingError.microBeatMissing
        }
        guard microBeats[microBeatIndex].selectedOption == nil else {
            throw SceneBeatMappingError.alreadyConfirmed
        }
        guard microBeats[microBeatIndex].options.contains(where: { $0.id == option.id }) else {
            throw SceneBeatMappingError.optionMissing
        }
        microBeats[microBeatIndex].selectedOptionID = option.id
        contract.microBeats = microBeats
        contract.updatedAt = .now
        project.touch()
    }

    static func screenplayScene(for contract: SceneContract) throws -> String {
        let microBeats = contract.microBeats.sorted()
        guard !microBeats.isEmpty,
              microBeats.allSatisfy({ $0.selectedOption != nil }) else {
            throw SceneBeatMappingError.incompletePlan
        }
        let body = microBeats.compactMap(\.selectedOption)
            .map(\.screenplayText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        return """
        \(contract.heading)

        \(body)
        """
    }
}

enum SceneBeatMappingError: LocalizedError {
    case microBeatMissing
    case optionMissing
    case alreadyConfirmed
    case incompletePlan

    var errorDescription: String? {
        switch self {
        case .microBeatMissing:
            "这个小节拍已经不存在。"
        case .optionMissing:
            "所选小节拍方案已经失效，请重新生成。"
        case .alreadyConfirmed:
            "这个小节拍已经确认。"
        case .incompletePlan:
            "请先确认这个场景的全部小节拍。"
        }
    }
}
