import Foundation

struct ScreenplaySceneReportItem: Identifiable, Hashable {
    var id: Int { sceneIndex }
    let sceneIndex: Int
    let heading: String
    let locationKind: FountainSceneLocationKind
    let locationName: String
    let timeOfDay: String
    let summary: String
    let characters: [String]
    let estimatedPages: Int
    let estimatedDurationSeconds: Double
}

struct ScreenplayCharacterReportItem: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let sceneCount: Int
    let dialogueCueCount: Int
}

struct ScreenplayLocationReportItem: Identifiable, Hashable {
    var id: String { "\(kind.rawValue)-\(name)" }
    let name: String
    let kind: FountainSceneLocationKind
    let sceneCount: Int
}

struct ScreenplayReport: Hashable {
    let scenes: [ScreenplaySceneReportItem]
    let characters: [ScreenplayCharacterReportItem]
    let locations: [ScreenplayLocationReportItem]
    let totalPages: Int
    let totalDurationSeconds: Double
    let interiorSceneCount: Int
    let exteriorSceneCount: Int
    let mixedSceneCount: Int
    let daySceneCount: Int
    let nightSceneCount: Int
    let totalCharacterCount: Int
}

enum ScreenplayReportBuilder {
    static func build(from text: String) -> ScreenplayReport {
        let snapshots = FountainParser.scenes(in: text)
        let scenes = snapshots.map { snapshot in
            let components = FountainParser.sceneHeadingComponents(snapshot.heading)
            return ScreenplaySceneReportItem(
                sceneIndex: snapshot.index,
                heading: snapshot.heading,
                locationKind: components?.locationKind ?? .unknown,
                locationName: components?.locationName ?? "未定地点",
                timeOfDay: components?.timeOfDay ?? "未标注",
                summary: snapshot.summary,
                characters: snapshot.characterNames,
                estimatedPages: snapshot.estimatedPages,
                estimatedDurationSeconds: snapshot.estimatedDurationSeconds
            )
        }

        var characterScenes: [String: Set<Int>] = [:]
        var characterCues: [String: Int] = [:]
        for snapshot in snapshots {
            for name in snapshot.characterNames {
                characterScenes[name, default: []].insert(snapshot.index)
            }
            for line in snapshot.text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard FountainParser.isCharacterCue(trimmed) else { continue }
                let name = trimmed.trimmingCharacters(
                    in: CharacterSet(charactersIn: "@^ ")
                )
                characterCues[name, default: 0] += 1
            }
        }
        let characters = characterScenes.keys.map { name in
            ScreenplayCharacterReportItem(
                name: name,
                sceneCount: characterScenes[name]?.count ?? 0,
                dialogueCueCount: characterCues[name] ?? 0
            )
        }
        .sorted {
            if $0.sceneCount != $1.sceneCount {
                return $0.sceneCount > $1.sceneCount
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        var locationCounts: [String: (String, FountainSceneLocationKind, Int)] = [:]
        for scene in scenes {
            let key = "\(scene.locationKind.rawValue)|\(scene.locationName)"
            let current = locationCounts[key]
                ?? (scene.locationName, scene.locationKind, 0)
            locationCounts[key] = (current.0, current.1, current.2 + 1)
        }
        let locations = locationCounts.values.map {
            ScreenplayLocationReportItem(
                name: $0.0,
                kind: $0.1,
                sceneCount: $0.2
            )
        }
        .sorted {
            if $0.sceneCount != $1.sceneCount {
                return $0.sceneCount > $1.sceneCount
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return ScreenplayReport(
            scenes: scenes,
            characters: characters,
            locations: locations,
            totalPages: scenes.reduce(0) { $0 + $1.estimatedPages },
            totalDurationSeconds: scenes.reduce(0) {
                $0 + $1.estimatedDurationSeconds
            },
            interiorSceneCount: scenes.count { $0.locationKind == .interior },
            exteriorSceneCount: scenes.count { $0.locationKind == .exterior },
            mixedSceneCount: scenes.count { $0.locationKind == .mixed },
            daySceneCount: scenes.count {
                $0.timeOfDay.contains("日") || $0.timeOfDay.contains("昼")
            },
            nightSceneCount: scenes.count {
                $0.timeOfDay.contains("夜") || $0.timeOfDay.contains("晚")
            },
            totalCharacterCount: characters.count
        )
    }
}
