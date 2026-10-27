import Foundation
import SwiftData

@MainActor
enum SourceMigration {
    struct Plan {
        var matches: [String: UUID] = [:]
        var skipped = 0
        var completed = 0
    }
    static func plan(from original: Manga, to chapters: [ChapterSummary]) -> Plan {
        var result = Plan()
        for target in chapters {
            let exact = original.chapters.filter { $0.name == target.name && $0.number == target.number }
            let sameTargets = chapters.filter { $0.name == target.name && $0.number == target.number }
            var match: Chapter?
            if exact.count == 1 && sameTargets.count == 1 { match = exact.first }
            else if let number = target.number, number.isFinite, number > 0 {
                let originals = original.chapters.filter { $0.number == number }
                let destinations = chapters.filter { $0.number == number }
                if originals.count == 1 && destinations.count == 1 { match = originals.first }
            }
            if let match {
                result.matches[target.id] = match.id
                if match.isRead { result.completed += 1 }
            } else { result.skipped += 1 }
        }
        return result
    }

    /// Adds a new edition; leaves the original, its downloads and partial-page positions intact.
    static func copy(original: Manga, destination: MangaSummary, sourceID: String,
                     chapters: [ChapterSummary], context: ModelContext,
                     allowed: ((String) -> Bool)? = nil,
                     save: ((ModelContext) throws -> Void)? = nil) throws -> Manga {
        guard allowed?(sourceID) ?? (SourceRegistry.source(id: sourceID) != nil) else {
            throw LibraryChangeError.unavailable
        }
        let all = try context.fetch(FetchDescriptor<Manga>())
        guard !all.contains(where: { $0.sourceID == sourceID && $0.remoteID == destination.id })
        else { throw LibraryChangeError.duplicate }
        guard !destination.id.isEmpty, !chapters.isEmpty, chapters.count <= 10_000,
              Set(chapters.map(\.id)).count == chapters.count,
              chapters.allSatisfy({ !$0.id.isEmpty && ($0.number?.isFinite ?? true) }) else {
            throw LibraryChangeError.ambiguous
        }
        let oldLinks = try context.fetch(FetchDescriptor<TrackLink>()).filter { $0.mangaID == original.id }
        let plan = plan(from: original, to: chapters)
        let entry = Manga(title: destination.title, coverData: original.coverData)
        entry.sourceID = sourceID; entry.remoteID = destination.id
        entry.categoryID = original.categoryID
        entry.directionRaw = original.directionRaw; entry.readerModeRaw = original.readerModeRaw
        context.insert(entry)
        var inserted: [Chapter] = []
        var links: [TrackLink] = []
        for item in chapters {
            let chapter = Chapter(name: item.name, number: item.number ?? 0, fileName: "", pageCount: 0)
            chapter.remoteID = item.id
            if let originalID = plan.matches[item.id],
               let old = original.chapters.first(where: { $0.id == originalID }) {
                chapter.isRead = old.isRead
            }
            context.insert(chapter); chapter.manga = entry; inserted.append(chapter)
        }
        for old in oldLinks {
            let link = TrackLink(mangaID: entry.id, trackerID: old.trackerID,
                                 remoteId: old.remoteId, remoteTitle: old.remoteTitle)
            context.insert(link); links.append(link)
        }
        do { if let save { try save(context) } else { try context.save() } }
        catch {
            links.forEach { context.delete($0) }
            inserted.forEach { context.delete($0) }
            context.delete(entry)
            context.processPendingChanges()
            throw error
        }
        return entry
    }
}
