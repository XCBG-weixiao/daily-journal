import SwiftUI
import AppKit

@MainActor
final class EditorTextController: NSObject, ObservableObject, NSTextViewDelegate {
    let view = FileDropTextView()
    let scroll = NSScrollView()
    let undo = UndoManager()
    private var changed: ((String) -> Void)?
    private var undoObservers: [NSObjectProtocol] = []
    override init() {
        super.init()
        view.isRichText = false; view.allowsUndo = true; view.usesFindPanel = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false; view.isAutomaticTextReplacementEnabled = false
        view.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = self; view.setAccessibilityLabel("Markdown 正文")
        scroll.hasVerticalScroller = true; scroll.documentView = view
        for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
            undoObservers.append(NotificationCenter.default.addObserver(forName: name, object: undo, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.changed?(self.view.string)
                }
            })
        }
    }
    deinit { for observer in undoObservers { NotificationCenter.default.removeObserver(observer) } }
    func configure(text: String, changed: @escaping (String) -> Void) {
        self.changed = changed
        if view.string != text {
            let selected = view.selectedRange()
            view.string = text
            view.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
        }
    }
    func insert(_ text: String) { view.insertText(text, replacementRange: view.selectedRange()) }
    func replace(_ text: String) { view.insertText(text, replacementRange: NSRange(location: 0, length: (view.string as NSString).length)) }
    func disconnect() { changed = nil; view.importFiles = nil; view.importBytes = nil }
    func textDidChange(_ notification: Notification) { changed?(view.string) }
    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}

struct MarkdownTextEditor: NSViewRepresentable {
    let controller: EditorTextController
    @Binding var text: String
    let importFiles: ([URL]) -> Void
    let importBytes: (Data) -> Void
    func makeNSView(context: Context) -> NSScrollView { configure(); return controller.scroll }
    func updateNSView(_ view: NSScrollView, context: Context) { configure() }
    private func configure() {
        let binding = _text
        controller.configure(text: text, changed: { binding.wrappedValue = $0 })
        controller.view.importFiles = importFiles; controller.view.importBytes = importBytes
    }
}
final class FileDropTextView: NSTextView {
    var importFiles: (([URL]) -> Void)?
    var importBytes: ((Data) -> Void)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return .copy }
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles?(urls); return true
        }
        return super.performDragOperation(sender)
    }
    override func paste(_ sender: Any?) {
        if let bytes = Self.imageBytes(from: NSPasteboard.general) { importBytes?(bytes); return }
        super.paste(sender)
    }
    static func imageBytes(from pasteboard: NSPasteboard) -> Data? {
        if let bytes = pasteboard.data(forType: .png) { return bytes }
        if let bytes = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: bytes),
           let png = bitmap.representation(using: .png, properties: [:]) { return png }
        return nil
    }
}
