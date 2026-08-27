import AppKit
import SwiftUI

enum ScreenplayEditorPalette {
    // StoryMentor 的 AI 共创工作区：深青色让正文、批注与生成状态保持同一视觉语境。
    static let workspace = Color(red: 0, green: 31.0 / 255.0, blue: 39.0 / 255.0)
    static let page = Color(red: 0, green: 43.0 / 255.0, blue: 54.0 / 255.0)
    static let chrome = Color(white: 37.0 / 255.0)
    static let statusBar = Color(white: 31.0 / 255.0)
    static let background = workspace

    static let workspaceNSColor = NSColor(
        red: 0,
        green: 31.0 / 255.0,
        blue: 39.0 / 255.0,
        alpha: 1
    )
    static let pageNSColor = NSColor(
        red: 0,
        green: 43.0 / 255.0,
        blue: 54.0 / 255.0,
        alpha: 1
    )
    static let primaryText = NSColor(
        red: 147.0 / 255.0,
        green: 161.0 / 255.0,
        blue: 161.0 / 255.0,
        alpha: 1
    )
    static let emphasizedText = NSColor(
        red: 238.0 / 255.0,
        green: 232.0 / 255.0,
        blue: 213.0 / 255.0,
        alpha: 1
    )
    static let secondaryText = NSColor(
        red: 111.0 / 255.0,
        green: 135.0 / 255.0,
        blue: 137.0 / 255.0,
        alpha: 1
    )
    static let insertionPoint = NSColor(
        red: 42.0 / 255.0,
        green: 161.0 / 255.0,
        blue: 152.0 / 255.0,
        alpha: 1
    )
}

private extension NSAttributedString.Key {
    static let screenplayElementStyleID = NSAttributedString.Key(
        "StoryMentor.ScreenplayElementStyleID"
    )
    static let screenplayExplicitElementStyleID = NSAttributedString.Key(
        "StoryMentor.ScreenplayExplicitElementStyleID"
    )
}

enum FountainReturnAction: Equatable {
    case systemDefault
    case insertNextElement
    case showElementMenu
}

/// Value-state boundary between the AppKit text system and SwiftUI chrome.
/// Keeping this explicit makes the element shown in the toolbar follow every
/// caret move instead of relying on observation through an imperative bridge.
struct FountainCursorContext: Equatable {
    let elementID: String
    let elementName: String
    let nextElementName: String
    let paragraphIndex: Int

    static let action = FountainCursorContext(
        elementID: ScreenplayElementStyleID.action,
        elementName: FountainElementType.action.rawValue,
        nextElementName: FountainElementType.action.rawValue,
        paragraphIndex: 0
    )
}

/// Pure policy for the Final Draft-style Return flow. Keeping this separate
/// makes the critical "Return to next element, Return again for chooser"
/// behavior executable in Debug invariants without replacing NSTextView.
enum FountainReturnPolicy {
    static func action(
        hasMarkedText: Bool,
        selectionLength: Int,
        paragraphIsEmpty: Bool,
        cursorAtParagraphEnd: Bool
    ) -> FountainReturnAction {
        guard !hasMarkedText, selectionLength == 0 else { return .systemDefault }
        if paragraphIsEmpty { return .showElementMenu }
        return cursorAtParagraphEnd ? .insertNextElement : .systemDefault
    }
}

@MainActor
@Observable
final class FountainEditorController {
    private(set) var currentElementID = ScreenplayElementStyleID.action
    private(set) var currentElementName = "动作"
    private(set) var nextElementName = "动作"
    private(set) var currentParagraphIndex = 0
    var manageStylesRequestID = UUID()

    fileprivate weak var coordinator: FountainTextEditor.Coordinator?

    func applyElement(_ styleID: String) {
        coordinator?.applyElement(styleID)
    }

    func showElementMenu() {
        coordinator?.showElementMenu()
    }

    fileprivate func requestStyleManagement() {
        manageStylesRequestID = UUID()
    }

    fileprivate func updateCursor(
        elementID: String,
        elementName: String,
        nextElementName: String,
        paragraphIndex: Int
    ) {
        guard currentElementID != elementID
                || currentElementName != elementName
                || self.nextElementName != nextElementName
                || currentParagraphIndex != paragraphIndex else {
            return
        }
        currentElementID = elementID
        currentElementName = elementName
        self.nextElementName = nextElementName
        currentParagraphIndex = paragraphIndex
    }

    /// Forces the AppKit-owned live buffer into SwiftUI before navigation,
    /// AI actions, import, or view dismissal.
    func flushEditing() -> String? {
        coordinator?.flushPendingChanges()
    }
}

private final class CenteredFountainTextView: NSTextView {
    private let preferredLineWidth: CGFloat = 780
    private let minimumHorizontalInset: CGFloat = 24
    private let verticalInset: CGFloat = 42
    var elementMenuProvider: (() -> NSMenu?)?
    var insertionPointDidMove: (() -> Void)?
    var zoomScale: CGFloat = 1 {
        didSet {
            if abs(oldValue - zoomScale) > 0.001 {
                needsLayout = true
            }
        }
    }

    override func layout() {
        super.layout()

        let horizontalInset = max(
            minimumHorizontalInset * zoomScale,
            (bounds.width - preferredLineWidth * zoomScale) / 2
        )
        let nextInset = NSSize(
            width: horizontalInset,
            height: verticalInset * zoomScale
        )
        guard abs(textContainerInset.width - nextInset.width) > 0.5
                || abs(textContainerInset.height - nextInset.height) > 0.5 else {
            return
        }
        textContainerInset = nextInset
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        elementMenuProvider?() ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // NSTextView's delegate notification is normally sufficient, but a
        // completed mouse tracking cycle is the one authoritative moment for
        // the final insertion point after a click or drag. Report it directly
        // so the SwiftUI element menu never displays the previous paragraph.
        insertionPointDidMove?()
    }
}

struct FountainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var paragraphAssignments: [ScreenplayParagraphElementAssignment]
    @Binding var cursorContext: FountainCursorContext
    let elementStyles: [ScreenplayElementStyleDefinition]
    let controller: FountainEditorController
    let focusSceneIndex: Int
    var zoomScale = 1.0
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ScreenplayEditorPalette.pageNSColor
        scrollView.borderType = .noBorder

        let textView = CenteredFountainTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 760)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 24, height: 42)
        textView.zoomScale = zoomScale
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.backgroundColor = ScreenplayEditorPalette.pageNSColor
        textView.textColor = ScreenplayEditorPalette.primaryText
        textView.insertionPointColor = ScreenplayEditorPalette.insertionPoint
        textView.selectedTextAttributes = [
            .backgroundColor: ScreenplayEditorPalette.insertionPoint
                .withAlphaComponent(0.34),
            .foregroundColor: ScreenplayEditorPalette.emphasizedText
        ]
        textView.setAccessibilityLabel("当前场景剧本正文")
        textView.string = text
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.lastRepresentedText = text
        controller.coordinator = context.coordinator
        textView.elementMenuProvider = { [weak coordinator = context.coordinator] in
            coordinator?.makeElementMenu()
        }
        textView.insertionPointDidMove = {
            [weak coordinator = context.coordinator] in
            coordinator?.updateCurrentElement()
        }
        context.coordinator.applyStyles()
        context.coordinator.focus(scene: focusSceneIndex)
        context.coordinator.updateCurrentElement()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        controller.coordinator = context.coordinator
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }

        var needsStyleRefresh = false
        let receivedExternalText = text != context.coordinator.lastRepresentedText
        if receivedExternalText {
            context.coordinator.cancelDeferredWork()
            let selection = textView.selectedRange()
            context.coordinator.isApplyingStyles = true
            textView.string = text
            textView.setSelectedRange(
                NSRange(
                    location: min(selection.location, (text as NSString).length),
                    length: 0
                )
            )
            context.coordinator.isApplyingStyles = false
            context.coordinator.lastRepresentedText = text
            context.coordinator.invalidateParagraphCache()
            needsStyleRefresh = true
        }
        if context.coordinator.lastAssignments != paragraphAssignments {
            needsStyleRefresh = true
        }
        if context.coordinator.lastElementStyles != elementStyles {
            context.coordinator.invalidateAttributeCache()
            needsStyleRefresh = true
        }
        if context.coordinator.lastFocusedScene != focusSceneIndex {
            context.coordinator.focus(scene: focusSceneIndex)
        }
        if context.coordinator.lastZoomScale != zoomScale {
            if let centeredTextView = textView as? CenteredFountainTextView {
                centeredTextView.zoomScale = zoomScale
            }
            context.coordinator.invalidateAttributeCache()
            needsStyleRefresh = true
        }
        if needsStyleRefresh {
            context.coordinator.applyStyles()
        }
        context.coordinator.updateCurrentElement()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FountainTextEditor
        weak var textView: NSTextView?
        var isApplyingStyles = false
        var lastFocusedScene = -1
        var lastZoomScale = 1.0
        var lastAssignments: [ScreenplayParagraphElementAssignment] = []
        var lastElementStyles: [ScreenplayElementStyleDefinition] = []
        var lastRepresentedText = ""
        var pendingEditedRange: NSRange?
        var textPublicationTask: Task<Void, Never>?
        var assignmentSyncTask: Task<Void, Never>?
        var cachedParagraphs: [FountainParagraphSnapshot]?
        var attributeCache: [String: [NSAttributedString.Key: Any]] = [:]
        var lastPublishedCursorContext: FountainCursorContext?

        init(_ parent: FountainTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingStyles, let textView else { return }
            invalidateParagraphCache()
            applyStyles(in: affectedParagraphRange())
            scheduleTextPublication(textView.string)
            scheduleAssignmentSynchronization()
            updateCurrentElement()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingStyles else { return }
            updateCurrentElement()
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            let replacementLength = ((replacementString ?? "") as NSString).length
            pendingEditedRange = NSRange(
                location: affectedCharRange.location,
                length: max(replacementLength, 1)
            )
            return true
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  let paragraph = currentParagraph() else {
                return false
            }

            let paragraphContentEnd = paragraph.utf16Range.location
                + paragraph.utf16Range.length
                - trailingLineBreakLength(in: paragraph.rawText)
            let action = FountainReturnPolicy.action(
                hasMarkedText: textView.hasMarkedText(),
                selectionLength: textView.selectedRange().length,
                paragraphIsEmpty: paragraph.trimmedText.isEmpty,
                cursorAtParagraphEnd: textView.selectedRange().location >= paragraphContentEnd
            )
            switch action {
            case .systemDefault:
                return false
            case .showElementMenu:
                showElementMenu()
                return true
            case .insertNextElement:
                let currentStyle = styleForParagraph(paragraph)
                let nextStyleID = style(withID: currentStyle.nextStyleID)?.id
                    ?? builtInStyleID(for: .action)
                textView.insertText(
                    "\n",
                    replacementRange: textView.selectedRange()
                )
                applyElement(nextStyleID)
                return true
            }
        }

        func focus(scene index: Int) {
            guard let textView else { return }
            lastFocusedScene = index
            let target = FountainParser.characterRange(
                forSceneAt: index,
                in: textView.string
            ) ?? NSRange(
                location: 0,
                length: min(textView.string.isEmpty ? 0 : 1, 1)
            )
            textView.scrollRangeToVisible(
                NSRange(location: target.location, length: min(target.length, 1))
            )
        }

        func applyElement(_ styleID: String) {
            guard let paragraph = currentParagraph(),
                  let style = style(withID: styleID) else { return }
            setAssignment(
                styleID: style.id,
                paragraphIndex: paragraph.index,
                fingerprint: paragraphFingerprint(paragraph.trimmedText)
            )
            applyStyles(in: paragraph.utf16Range)
            publishTextIfNeeded()
            synchronizeAssignmentsFromTextStorage()
            updateCurrentElement()
            textView?.window?.makeFirstResponder(textView)
        }

        func showElementMenu() {
            guard let textView, let menu = makeElementMenu() else { return }
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                let selection = textView.selectedRange()
                let screenRect = textView.firstRect(
                    forCharacterRange: NSRange(
                        location: min(selection.location, textView.string.utf16.count),
                        length: 0
                    ),
                    actualRange: nil
                )
                guard let window = textView.window else { return }
                let windowPoint = window.convertPoint(
                    fromScreen: NSPoint(x: screenRect.minX, y: screenRect.minY)
                )
                let localPoint = textView.convert(windowPoint, from: nil)
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: localPoint.x, y: localPoint.y),
                    in: textView
                )
                self.updateCurrentElement()
            }
        }

        func makeElementMenu() -> NSMenu? {
            guard !parent.elementStyles.isEmpty else { return nil }
            let menu = NSMenu(title: "剧本元素")
            menu.autoenablesItems = false
            for style in parent.elementStyles {
                let prefix = style.shortcutKey
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                    ? ""
                    : "\(style.shortcutHint)　"
                let item = NSMenuItem(
                    title: "\(prefix)\(style.displayName)",
                    action: #selector(selectElementFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = style.id
                item.state = style.id == parent.controller.currentElementID
                    ? .on
                    : .off
                item.isEnabled = true
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let settings = NSMenuItem(
                title: "管理元素样式…",
                action: #selector(openElementSettings(_:)),
                keyEquivalent: ","
            )
            settings.target = self
            menu.addItem(settings)
            return menu
        }

        @objc private func selectElementFromMenu(_ sender: NSMenuItem) {
            guard let styleID = sender.representedObject as? String else { return }
            applyElement(styleID)
        }

        @objc private func openElementSettings(_ sender: NSMenuItem) {
            parent.controller.requestStyleManagement()
        }

        func applyStyles(in requestedRange: NSRange? = nil) {
            guard let textView,
                  let storage = textView.textStorage else { return }
            let selectedRange = textView.selectedRange()
            lastZoomScale = parent.zoomScale
            lastAssignments = parent.paragraphAssignments
            lastElementStyles = parent.elementStyles

            isApplyingStyles = true
            storage.beginEditing()

            let baseStyle = style(withID: builtInStyleID(for: .action))
                ?? parent.elementStyles.first
            for paragraph in paragraphSnapshots() {
                guard paragraph.utf16Range.length > 0 else { continue }
                guard requestedRange == nil
                        || NSIntersectionRange(
                            paragraph.utf16Range,
                            requestedRange!
                        ).length > 0 else {
                    continue
                }

                let explicitStyleID = explicitStyleID(for: paragraph)
                let resolvedStyle = explicitStyleID.flatMap {
                    style(withID: $0)
                }
                    ?? styleForParagraph(paragraph)

                if let baseStyle {
                    storage.setAttributes(
                        attributes(for: baseStyle),
                        range: paragraph.utf16Range
                    )
                }
                storage.addAttributes(
                    attributes(for: resolvedStyle),
                    range: paragraph.utf16Range
                )
                if let explicitStyleID,
                   style(withID: explicitStyleID) != nil {
                    storage.addAttribute(
                        .screenplayExplicitElementStyleID,
                        value: explicitStyleID,
                        range: paragraph.utf16Range
                    )
                } else {
                    storage.removeAttribute(
                        .screenplayExplicitElementStyleID,
                        range: paragraph.utf16Range
                    )
                }
            }

            storage.endEditing()
            textView.setSelectedRange(
                NSRange(
                    location: min(selectedRange.location, storage.length),
                    length: min(
                        selectedRange.length,
                        max(storage.length - selectedRange.location, 0)
                    )
                )
            )
            isApplyingStyles = false
            pendingEditedRange = nil
            updateTypingAttributes()
        }

        func updateCurrentElement() {
            guard let paragraph = currentParagraph() else { return }
            let style = styleForParagraph(paragraph)
            let next = self.style(withID: style.nextStyleID)
            let context = FountainCursorContext(
                elementID: style.id,
                elementName: style.displayName,
                nextElementName: next?.displayName
                    ?? FountainElementType.action.rawValue,
                paragraphIndex: paragraph.index
            )
            parent.controller.updateCursor(
                elementID: style.id,
                elementName: context.elementName,
                nextElementName: context.nextElementName,
                paragraphIndex: paragraph.index
            )
            publishCursorContext(context)
            updateTypingAttributes(style)
        }

        private func publishCursorContext(_ context: FountainCursorContext) {
            guard lastPublishedCursorContext != context else { return }
            lastPublishedCursorContext = context
            // updateCurrentElement is also called from updateNSView. Publish on
            // the next main-actor turn so SwiftUI never receives a state write
            // during its own representable update pass.
            Task { @MainActor [weak self] in
                guard let self, self.parent.cursorContext != context else {
                    return
                }
                self.parent.cursorContext = context
            }
        }

        private func currentParagraph() -> FountainParagraphSnapshot? {
            guard let textView else { return nil }
            let location = textView.selectedRange().location
            let length = (textView.string as NSString).length
            guard location >= 0, location <= length else { return nil }
            let snapshots = paragraphSnapshots()
            if location == length { return snapshots.last }
            return snapshots.first {
                location >= $0.utf16Range.location
                    && location < NSMaxRange($0.utf16Range)
            }
        }

        private func updateTypingAttributes(
            _ explicitStyle: ScreenplayElementStyleDefinition? = nil
        ) {
            guard let textView else { return }
            let paragraph = currentParagraph()
            let style = explicitStyle
                ?? paragraph.map(styleForParagraph)
                ?? self.style(withID: builtInStyleID(for: .action))
            if let style {
                var typingAttributes = attributes(for: style)
                if let paragraph,
                   let explicitStyleID = explicitStyleID(for: paragraph) {
                    typingAttributes[.screenplayExplicitElementStyleID] =
                        explicitStyleID
                }
                textView.typingAttributes = typingAttributes
            }
        }

        private func styleForParagraph(
            _ paragraph: FountainParagraphSnapshot
        ) -> ScreenplayElementStyleDefinition {
            if let explicitStyleID = explicitStyleID(for: paragraph),
               let explicitStyle = style(withID: explicitStyleID) {
                return explicitStyle
            }

            let inferredID = builtInStyleID(for: paragraph.inferredType)
            return style(withID: inferredID)
                ?? parent.elementStyles.first {
                    $0.baseType == paragraph.inferredType
                }
                ?? parent.elementStyles.first
                ?? ScreenplayElementStyleDefinition.defaultStyles[0]
        }

        private func style(
            withID styleID: String?
        ) -> ScreenplayElementStyleDefinition? {
            guard let styleID else { return nil }
            return parent.elementStyles.first { $0.id == styleID }
        }

        private func builtInStyleID(for type: FountainElementType) -> String {
            switch type {
            case .sceneHeading: ScreenplayElementStyleID.sceneHeading
            case .action: ScreenplayElementStyleID.action
            case .character: ScreenplayElementStyleID.character
            case .parenthetical: ScreenplayElementStyleID.parenthetical
            case .dialogue: ScreenplayElementStyleID.dialogue
            case .transition: ScreenplayElementStyleID.transition
            case .note: ScreenplayElementStyleID.note
            }
        }

        private func setAssignment(
            styleID: String,
            paragraphIndex: Int,
            fingerprint: String
        ) {
            var assignments = parent.paragraphAssignments
            assignments.removeAll { $0.paragraphIndex == paragraphIndex }
            assignments.append(
                ScreenplayParagraphElementAssignment(
                    paragraphIndex: paragraphIndex,
                    elementStyleID: styleID,
                    textFingerprint: fingerprint
                )
            )
            assignments.sort { $0.paragraphIndex < $1.paragraphIndex }
            lastAssignments = assignments
            parent.paragraphAssignments = assignments
        }

        private func synchronizeAssignmentsFromTextStorage() {
            guard let textView, let storage = textView.textStorage else { return }
            let previous = parent.paragraphAssignments
            let paragraphs = paragraphSnapshots()
            var attributedStyleIDs: [Int: String] = [:]

            for paragraph in paragraphs {
                if paragraph.utf16Range.length > 0,
                   paragraph.utf16Range.location < storage.length,
                   let explicitStyleID = storage.attribute(
                        .screenplayExplicitElementStyleID,
                        at: paragraph.utf16Range.location,
                        effectiveRange: nil
                    ) as? String {
                    attributedStyleIDs[paragraph.index] = explicitStyleID
                }
            }

            let assignments = ScreenplayParagraphAssignmentReconciler.reconcile(
                paragraphs: paragraphs,
                previous: previous,
                attributedStyleIDs: attributedStyleIDs,
                validStyleIDs: Set(parent.elementStyles.map(\.id))
            )

            if assignments != previous {
                lastAssignments = assignments
                parent.paragraphAssignments = assignments
            }
        }

        private func attributes(
            for style: ScreenplayElementStyleDefinition
        ) -> [NSAttributedString.Key: Any] {
            if let cached = attributeCache[style.id] {
                return cached
            }
            let scale = min(max(parent.zoomScale, 0.75), 2.0)
            let size = CGFloat(style.fontSize) * scale
            var font = NSFont(name: style.fontName, size: size)
                ?? NSFont(name: "Courier Final Draft", size: size)
                ?? NSFont(name: "Courier Prime", size: size)
                ?? NSFont(name: "Courier", size: size)
                ?? .monospacedSystemFont(ofSize: size, weight: .regular)

            var traits: NSFontTraitMask = []
            if style.isBold { traits.insert(.boldFontMask) }
            if style.isItalic { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                font = NSFontManager.shared.convert(font, toHaveTrait: traits)
            }

            let paragraph = NSMutableParagraphStyle()
            let contentLeftInches = 1.0
            let contentRightInches = 7.5
            let leftIndent = max(
                0,
                CGFloat(style.leftIndentInches - contentLeftInches) * 72 * scale
            )
            paragraph.alignment = style.alignment.nsTextAlignment
            paragraph.headIndent = leftIndent
            paragraph.firstLineHeadIndent = leftIndent
                + (style.baseType == .parenthetical ? -7.2 * scale : 0)
            paragraph.tailIndent = min(
                0,
                CGFloat(style.rightBoundaryInches - contentRightInches) * 72 * scale
            )
            paragraph.paragraphSpacingBefore = CGFloat(style.spacingBefore) * scale
            paragraph.paragraphSpacing = CGFloat(style.spacingAfter) * scale
            paragraph.lineHeightMultiple = CGFloat(max(style.lineSpacing, 0.8))

            let foreground: NSColor
            switch style.baseType {
            case .sceneHeading, .character, .transition:
                foreground = ScreenplayEditorPalette.emphasizedText
            case .parenthetical, .note:
                foreground = ScreenplayEditorPalette.secondaryText
            case .action, .dialogue:
                foreground = ScreenplayEditorPalette.primaryText
            }

            let result: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: foreground,
                .paragraphStyle: paragraph,
                .screenplayElementStyleID: style.id
            ]
            attributeCache[style.id] = result
            return result
        }

        func flushPendingChanges() -> String? {
            guard let textView else { return nil }
            cancelDeferredWork()
            invalidateParagraphCache()
            synchronizeAssignmentsFromTextStorage()
            let value = textView.string
            if value != lastRepresentedText {
                lastRepresentedText = value
                parent.text = value
            }
            return value
        }

        func cancelDeferredWork() {
            textPublicationTask?.cancel()
            textPublicationTask = nil
            assignmentSyncTask?.cancel()
            assignmentSyncTask = nil
        }

        func invalidateParagraphCache() {
            cachedParagraphs = nil
        }

        func invalidateAttributeCache() {
            attributeCache.removeAll(keepingCapacity: true)
        }

        private func paragraphSnapshots() -> [FountainParagraphSnapshot] {
            if let cachedParagraphs {
                return cachedParagraphs
            }
            let snapshots = FountainParser.paragraphs(in: textView?.string ?? "")
            cachedParagraphs = snapshots
            return snapshots
        }

        private func explicitStyleID(
            for paragraph: FountainParagraphSnapshot
        ) -> String? {
            var attributedStyleID: String?
            if let storage = textView?.textStorage,
               paragraph.utf16Range.length > 0,
               paragraph.utf16Range.location < storage.length {
                attributedStyleID = storage.attribute(
                    .screenplayExplicitElementStyleID,
                    at: paragraph.utf16Range.location,
                    effectiveRange: nil
                ) as? String
            }
            return ScreenplayParagraphAssignmentReconciler.explicitStyleID(
                for: paragraph,
                assignments: parent.paragraphAssignments,
                attributedStyleID: attributedStyleID,
                validStyleIDs: Set(parent.elementStyles.map(\.id))
            )
        }

        private func affectedParagraphRange() -> NSRange? {
            guard let textView else { return nil }
            let value = textView.string as NSString
            guard value.length > 0 else { return nil }
            let edit = pendingEditedRange ?? textView.selectedRange()
            let start = min(max(edit.location - 1, 0), value.length - 1)
            let end = min(
                max(edit.location + max(edit.length, 1) + 1, start + 1),
                value.length
            )
            return value.lineRange(
                for: NSRange(location: start, length: max(end - start, 0))
            )
        }

        private func scheduleTextPublication(_ value: String) {
            textPublicationTask?.cancel()
            textPublicationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self else { return }
                self.publishTextIfNeeded(expected: value)
            }
        }

        private func publishTextIfNeeded(expected: String? = nil) {
            guard let textView else { return }
            let value = textView.string
            if let expected, value != expected { return }
            guard value != lastRepresentedText else { return }
            lastRepresentedText = value
            parent.text = value
        }

        private func scheduleAssignmentSynchronization() {
            assignmentSyncTask?.cancel()
            assignmentSyncTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(260))
                guard !Task.isCancelled, let self else { return }
                self.synchronizeAssignmentsFromTextStorage()
            }
        }

        private func paragraphFingerprint(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func trailingLineBreakLength(in text: String) -> Int {
            if text.hasSuffix("\r\n") { return 2 }
            if text.hasSuffix("\n") || text.hasSuffix("\r") { return 1 }
            return 0
        }
    }
}
