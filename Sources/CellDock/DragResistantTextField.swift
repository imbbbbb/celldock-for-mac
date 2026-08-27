import AppKit
import SwiftUI

/// A text field that keeps mouse drags to itself.
///
/// The communication window has no visible title bar, so it deliberately opts
/// into `isMovableByWindowBackground` to stay draggable. AppKit decides whether
/// a `mouseDown` starts a window drag by asking the hit view's
/// `mouseDownCanMoveWindow`, whose default depends on opacity rather than on
/// being a control — and SwiftUI's own `TextField` answers yes. The visible
/// effect is that dragging to select text moves the window instead, which was
/// reported from the AT console and would recur in every field added to this
/// window.
///
/// Dropping to `NSTextField` and overriding that property fixes selection in
/// the field without taking background dragging away from the rest of the
/// window. Placing a blocking view behind a SwiftUI `TextField` does not work:
/// the hit test never reaches it.
struct DragResistantTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Programmatic focus control. Omit it to let AppKit handle focus normally,
    /// which is what an ordinary field wants.
    var focus: Binding<Bool>?
    var isMonospaced = false
    var onSubmit: () -> Void = {}

    private final class ResistantField: NSTextField {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = ResistantField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = isMonospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : .systemFont(ofSize: NSFont.systemFontSize)
        field.bezelStyle = .roundedBezel
        field.isBezeled = true
        field.isEditable = true
        field.isSelectable = true
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        guard let focus, let window = nsView.window else { return }
        let editor = nsView.currentEditor()
        let hasFocus = editor != nil && window.firstResponder === editor
        guard hasFocus != focus.wrappedValue else { return }
        // Deferred: changing first responder inside a SwiftUI update pass can
        // re-enter this update.
        DispatchQueue.main.async {
            guard nsView.window === window else { return }
            window.makeFirstResponder(focus.wrappedValue ? nsView : nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DragResistantTextField

        init(_ parent: DragResistantTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.onSubmit()
            return true
        }
    }
}
