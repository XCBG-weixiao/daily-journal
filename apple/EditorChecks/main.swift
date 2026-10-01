import AppKit
import SwiftUI

struct EditorCheckFailure: Error { let message: String }

@main
struct EditorChecks {
    @MainActor
    static func main() throws {
        var passed = 0
        func expect(_ value: Bool, _ message: String) throws {
            guard value else { throw EditorCheckFailure(message: message) }
            passed += 1; print("PASS \(passed): \(message)"); fflush(stdout)
        }
        let controller = EditorTextController()
        var body = "第一段\n第二段"
        controller.configure(text: body, changed: { body = $0 })
        controller.undo.groupsByEvent = false
        try expect(controller.view.allowsUndo, "production editor enables undo")
        try expect(controller.view.usesFindPanel, "production editor provides native find")
        controller.view.setSelectedRange(NSRange(location: 3, length: 0))
        controller.undo.beginUndoGrouping()
        controller.insert("新增文字")
        controller.undo.endUndoGrouping()
        try expect(body == "第一段新增文字\n第二段", "insertion uses current cursor and updates draft")
        try expect(controller.undo.canUndo, "typing registers an undo operation")
        controller.undo.undo()
        try expect(body == "第一段\n第二段", "Command-Z responder operation restores text and draft binding")
        controller.undo.redo()
        try expect(body == "第一段新增文字\n第二段", "redo restores inserted text")
        let originalView = controller.view
        let originalScroll = controller.scroll
        controller.configure(text: body, changed: { body = $0 })
        try expect(controller.view === originalView && controller.scroll === originalScroll && controller.undo.canUndo, "preview remount reuses text view, cursor and undo history")
        controller.view.setSelectedRange(NSRange(location: (body as NSString).length, length: 0))
        controller.undo.beginUndoGrouping()
        controller.insert("\n![图片](../assets/10000000-0000-4000-8000-000000000001/image.png)\n")
        controller.undo.endUndoGrouping()
        let inserted = body
        controller.configure(text: inserted, changed: { body = $0 })
        controller.configure(text: inserted, changed: { body = $0 })
        try expect(body.components(separatedBy: "![图片]").count == 2, "reconfiguring editor never replays image insertion")
        controller.undo.undo()
        try expect(!body.contains("![图片]"), "image insertion is undoable")
        controller.undo.redo()
        try expect(body.contains("![图片]"), "image insertion is redoable")
        controller.undo.beginUndoGrouping()
        controller.replace("替换后的正文")
        controller.undo.endUndoGrouping()
        try expect(body == "替换后的正文", "image removal and replacement update draft through text view")
        controller.undo.undo()
        try expect(body == inserted, "programmatic editing remains undoable")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("普通文字", forType: .string)
        try expect(FileDropTextView.imageBytes(from: pasteboard) == nil, "plain text paste continues through native text handling")
        pasteboard.clearContents()
        let bytes = Data([1,2,3,4])
        pasteboard.setData(bytes, forType: .png)
        try expect(FileDropTextView.imageBytes(from: pasteboard) == bytes, "PNG clipboard content is passed to repository image validation")
        controller.disconnect()
        print("\n\(passed) production editor checks passed. User clipboard was not changed.")
    }
}
