import Foundation

final class DirectoryPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let changed: () -> Void
    init(url: URL, changed: @escaping () -> Void) {
        presentedItemURL = url
        self.changed = changed
    }
    func presentedItemDidChange() { changed() }
    func presentedSubitemDidAppear(at url: URL) { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func presentedItemDidMove(to newURL: URL) { changed() }
    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        changed()
        completionHandler(nil)
    }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        changed()
        completionHandler(nil)
    }
    func presentedSubitem(at url: URL, didGain version: NSFileVersion) { changed() }
    func presentedSubitem(at url: URL, didResolve version: NSFileVersion) { changed() }
}
