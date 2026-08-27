import AppKit
import Foundation

enum ScreenplayElementTextAlignment: String, CaseIterable, Codable, Hashable, Identifiable {
    case left
    case center
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left: "左对齐"
        case .center: "居中"
        case .right: "右对齐"
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}

enum ScreenplayElementStyleID {
    static let general = "builtin.general"
    static let sceneHeading = "builtin.scene-heading"
    static let action = "builtin.action"
    static let character = "builtin.character"
    static let parenthetical = "builtin.parenthetical"
    static let dialogue = "builtin.dialogue"
    static let transition = "builtin.transition"
    static let shot = "builtin.shot"
    static let note = "builtin.note"
}

struct ScreenplayElementStyleDefinition: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var baseTypeRawValue: String

    var fontName: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var isUppercase: Bool

    var alignment: ScreenplayElementTextAlignment
    var leftIndentInches: Double
    var rightBoundaryInches: Double
    var spacingBefore: Double
    var spacingAfter: Double
    var lineSpacing: Double

    var nextStyleID: String
    var startsNewPage: Bool
    var isBuiltIn: Bool

    var shortcutKey: String
    var shortcutUsesCommand: Bool
    var shortcutUsesControl: Bool
    var shortcutUsesOption: Bool
    var shortcutUsesShift: Bool

    init(
        id: String,
        name: String,
        baseTypeRawValue: String,
        fontName: String = "Courier Final Draft",
        fontSize: Double = 12,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUppercase: Bool = false,
        alignment: ScreenplayElementTextAlignment = .left,
        leftIndentInches: Double = 1.5,
        rightBoundaryInches: Double = 7.5,
        spacingBefore: Double = 0,
        spacingAfter: Double = 5,
        lineSpacing: Double = 1,
        nextStyleID: String,
        startsNewPage: Bool = false,
        isBuiltIn: Bool,
        shortcutKey: String = "",
        shortcutUsesCommand: Bool = true,
        shortcutUsesControl: Bool = true,
        shortcutUsesOption: Bool = false,
        shortcutUsesShift: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseTypeRawValue = baseTypeRawValue
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUppercase = isUppercase
        self.alignment = alignment
        self.leftIndentInches = leftIndentInches
        self.rightBoundaryInches = rightBoundaryInches
        self.spacingBefore = spacingBefore
        self.spacingAfter = spacingAfter
        self.lineSpacing = lineSpacing
        self.nextStyleID = nextStyleID
        self.startsNewPage = startsNewPage
        self.isBuiltIn = isBuiltIn
        self.shortcutKey = shortcutKey
        self.shortcutUsesCommand = shortcutUsesCommand
        self.shortcutUsesControl = shortcutUsesControl
        self.shortcutUsesOption = shortcutUsesOption
        self.shortcutUsesShift = shortcutUsesShift
    }

    var baseType: FountainElementType {
        get { FountainElementType(rawValue: baseTypeRawValue) ?? .action }
        set { baseTypeRawValue = newValue.rawValue }
    }

    /// A persisted custom style may temporarily have an empty editable name.
    /// Editor chrome must still expose a useful element type at all times.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.defaultStyle(id: id)?.name ?? baseType.rawValue
    }

    var shortcutHint: String {
        let key = shortcutKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !key.isEmpty else { return "未设置" }

        var parts: [String] = []
        if shortcutUsesControl { parts.append("⌃") }
        if shortcutUsesOption { parts.append("⌥") }
        if shortcutUsesShift { parts.append("⇧") }
        if shortcutUsesCommand { parts.append("⌘") }
        parts.append(key)
        return parts.joined()
    }

    static let defaultStyles: [ScreenplayElementStyleDefinition] = [
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.general,
            name: "常规",
            baseTypeRawValue: FountainElementType.action.rawValue,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.general,
            isBuiltIn: true,
            shortcutKey: "0"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.sceneHeading,
            name: "场景标题",
            baseTypeRawValue: FountainElementType.sceneHeading.rawValue,
            isBold: true,
            isUppercase: true,
            spacingBefore: 24,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.action,
            startsNewPage: false,
            isBuiltIn: true,
            shortcutKey: "1"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.action,
            name: "动作",
            baseTypeRawValue: FountainElementType.action.rawValue,
            spacingBefore: 12,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.action,
            isBuiltIn: true,
            shortcutKey: "2"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.character,
            name: "人物",
            baseTypeRawValue: FountainElementType.character.rawValue,
            isBold: true,
            isUppercase: true,
            leftIndentInches: 3.5,
            rightBoundaryInches: 7.25,
            spacingBefore: 12,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.dialogue,
            isBuiltIn: true,
            shortcutKey: "3"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.parenthetical,
            name: "括注",
            baseTypeRawValue: FountainElementType.parenthetical.rawValue,
            leftIndentInches: 3,
            rightBoundaryInches: 5.5,
            spacingBefore: 0,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.dialogue,
            isBuiltIn: true,
            shortcutKey: "4"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.dialogue,
            name: "对白",
            baseTypeRawValue: FountainElementType.dialogue.rawValue,
            leftIndentInches: 2.5,
            rightBoundaryInches: 6,
            spacingBefore: 0,
            spacingAfter: 6,
            nextStyleID: ScreenplayElementStyleID.action,
            isBuiltIn: true,
            shortcutKey: "5"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.transition,
            name: "转场",
            baseTypeRawValue: FountainElementType.transition.rawValue,
            isBold: true,
            isUppercase: true,
            alignment: .right,
            leftIndentInches: 5.5,
            rightBoundaryInches: 7.1,
            spacingBefore: 12,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.sceneHeading,
            isBuiltIn: true,
            shortcutKey: "6"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.shot,
            name: "镜头",
            baseTypeRawValue: FountainElementType.action.rawValue,
            isBold: true,
            isUppercase: true,
            spacingBefore: 12,
            spacingAfter: 0,
            nextStyleID: ScreenplayElementStyleID.action,
            isBuiltIn: true,
            shortcutKey: "7"
        ),
        ScreenplayElementStyleDefinition(
            id: ScreenplayElementStyleID.note,
            name: "注释",
            baseTypeRawValue: FountainElementType.note.rawValue,
            fontSize: 10,
            isItalic: true,
            spacingBefore: 3,
            spacingAfter: 3,
            nextStyleID: ScreenplayElementStyleID.note,
            isBuiltIn: true,
            shortcutKey: "4",
            shortcutUsesControl: true
        )
    ]

    static func defaultStyle(
        id: String
    ) -> ScreenplayElementStyleDefinition? {
        defaultStyles.first { $0.id == id }
    }

    func customCopy(named customName: String? = nil) -> ScreenplayElementStyleDefinition {
        var copy = self
        copy.id = "custom.\(UUID().uuidString.lowercased())"
        copy.name = customName ?? "\(name) 副本"
        copy.isBuiltIn = false
        copy.shortcutKey = ""
        copy.shortcutUsesCommand = true
        copy.shortcutUsesControl = false
        copy.shortcutUsesOption = false
        copy.shortcutUsesShift = false
        return copy
    }
}

struct ScreenplayParagraphElementAssignment: Codable, Hashable, Identifiable {
    var id: UUID
    var paragraphIndex: Int
    var elementStyleID: String
    var textFingerprint: String

    init(
        id: UUID = UUID(),
        paragraphIndex: Int,
        elementStyleID: String,
        textFingerprint: String
    ) {
        self.id = id
        self.paragraphIndex = paragraphIndex
        self.elementStyleID = elementStyleID
        self.textFingerprint = textFingerprint
    }
}

/// Reconciles explicit element choices with TextKit attributes after edits.
/// The persisted assignment is the source of truth; attributed-string markers
/// only carry that identity across paragraph insertion and deletion.
enum ScreenplayParagraphAssignmentReconciler {
    static func explicitStyleID(
        for paragraph: FountainParagraphSnapshot,
        assignments: [ScreenplayParagraphElementAssignment],
        attributedStyleID: String?,
        validStyleIDs: Set<String>
    ) -> String? {
        if let attributedStyleID,
           validStyleIDs.contains(attributedStyleID) {
            return attributedStyleID
        }
        return matchingAssignment(
            for: paragraph,
            assignments: assignments,
            validStyleIDs: validStyleIDs
        )?.elementStyleID
    }

    static func reconcile(
        paragraphs: [FountainParagraphSnapshot],
        previous: [ScreenplayParagraphElementAssignment],
        attributedStyleIDs: [Int: String],
        validStyleIDs: Set<String>
    ) -> [ScreenplayParagraphElementAssignment] {
        var usedAssignmentIDs = Set<UUID>()
        var result: [ScreenplayParagraphElementAssignment] = []

        for paragraph in paragraphs {
            let attributedStyleID = attributedStyleIDs[paragraph.index]
                .flatMap { validStyleIDs.contains($0) ? $0 : nil }
            let previousAssignment = matchingAssignment(
                for: paragraph,
                assignments: previous.filter {
                    !usedAssignmentIDs.contains($0.id)
                },
                validStyleIDs: validStyleIDs
            )
            let styleID = attributedStyleID
                ?? previousAssignment?.elementStyleID
            guard let styleID else { continue }

            let reusable = previousAssignment.flatMap {
                $0.elementStyleID == styleID ? $0 : nil
            } ?? previous.first {
                !usedAssignmentIDs.contains($0.id)
                    && $0.paragraphIndex == paragraph.index
                    && $0.elementStyleID == styleID
            }
            if let reusable {
                usedAssignmentIDs.insert(reusable.id)
            }
            result.append(
                ScreenplayParagraphElementAssignment(
                    id: reusable?.id ?? UUID(),
                    paragraphIndex: paragraph.index,
                    elementStyleID: styleID,
                    textFingerprint: fingerprint(paragraph.trimmedText)
                )
            )
        }

        return result.sorted { $0.paragraphIndex < $1.paragraphIndex }
    }

    private static func matchingAssignment(
        for paragraph: FountainParagraphSnapshot,
        assignments: [ScreenplayParagraphElementAssignment],
        validStyleIDs: Set<String>
    ) -> ScreenplayParagraphElementAssignment? {
        let paragraphFingerprint = fingerprint(paragraph.trimmedText)
        if let positional = assignments.first(where: {
            $0.paragraphIndex == paragraph.index
                && validStyleIDs.contains($0.elementStyleID)
                && (
                    paragraph.trimmedText.isEmpty
                        || $0.textFingerprint.isEmpty
                        || $0.textFingerprint == paragraphFingerprint
                )
        }) {
            return positional
        }

        guard !paragraphFingerprint.isEmpty else { return nil }
        let fingerprintMatches = assignments.filter {
            validStyleIDs.contains($0.elementStyleID)
                && $0.textFingerprint == paragraphFingerprint
        }
        return fingerprintMatches.count == 1 ? fingerprintMatches[0] : nil
    }

    private static func fingerprint(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
