import Photos
import UIKit

/// Reads the photo library for synced widgets: the albums there are, which photos an album or
/// On This Day widget should hold, and their image data. Only used once the user turns syncing
/// on for a widget; hand-picked widgets never touch the library.
nonisolated enum PhotoLibrarySync {
    /// The background refresh that keeps synced widgets current while the app isn't open.
    static let refreshTaskID = "Adrian.Photo-Widget.sync"
    /// On This Day prepares a week of memories, so the widget moves on at midnight by itself even
    /// on days the app doesn't get to run.
    static let daysAhead = 7

    struct Album: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let count: Int
        let coverID: String?
    }

    struct Planned: Hashable, Sendable {
        let assetID: String
        /// For On This Day: the day ("MM-dd") the photo belongs to.
        let day: String?
        /// When the library says it was taken, for photos whose file carries no date (screenshots, saved images).
        var created: Date? = nil
    }

    // MARK: - Access

    static var hasAccess: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    static var isLimited: Bool {
        PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
    }

    /// Asks the first time; after that it just reports what the user decided.
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // MARK: - Albums

    /// Useful smart albums first, then the user's own albums by name. Empty ones are left out.
    static func albums() -> [Album] {
        var smart: [Album] = []
        let subtypes: [PHAssetCollectionSubtype] = [
            .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumSelfPortraits, .smartAlbumDepthEffect, .smartAlbumPanoramas,
        ]
        for subtype in subtypes {
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil).enumerateObjects { collection, _, _ in
                if let album = album(collection) { smart.append(album) }
            }
        }
        var mine: [Album] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
            if let album = album(collection) { mine.append(album) }
        }
        return smart + mine.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func album(_ collection: PHAssetCollection) -> Album? {
        let assets = PHAsset.fetchAssets(in: collection, options: imagesNewestFirst())
        guard assets.count > 0 else { return nil }
        return Album(id: collection.localIdentifier, title: collection.localizedTitle ?? String(localized: "Album"),
                     count: assets.count, coverID: assets.firstObject?.localIdentifier)
    }

    // MARK: - Planning

    /// The photos a synced widget should hold right now, in display order. `nil` when there's
    /// nothing to go on (no access, or the album was deleted), so the widget keeps what it has.
    static func plan(for source: PhotoSource, from date: Date = .now, limit: Int = PhotoWidgetConfig.maxPhotos,
                     calendar: Calendar = .current) -> [Planned]? {
        guard hasAccess else { return nil }
        switch source {
        case .picked:
            return nil
        case .album(let id, _):
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let options = imagesNewestFirst()
            options.fetchLimit = limit
            var planned: [Planned] = []
            PHAsset.fetchAssets(in: collection, options: options).enumerateObjects { asset, _, _ in
                planned.append(Planned(assetID: asset.localIdentifier, day: nil, created: asset.creationDate))
            }
            return planned
        case .onThisDay:
            let perDay = max(limit / daysAhead, 1)
            var planned: [Planned] = []
            for offset in 0..<daysAhead {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
                let ranges = pastYearRanges(sameDayAs: day, calendar: calendar)
                guard !ranges.isEmpty else { continue }
                let options = imagesNewestFirst()
                options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue),
                    NSCompoundPredicate(orPredicateWithSubpredicates: ranges.map {
                        NSPredicate(format: "creationDate >= %@ AND creationDate < %@", $0.start as NSDate, $0.end as NSDate)
                    }),
                ])
                var found: [(id: String, year: Int)] = []
                var created: [String: Date] = [:]
                PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                    guard let date = asset.creationDate else { return }
                    found.append((asset.localIdentifier, calendar.component(.year, from: date)))
                    created[asset.localIdentifier] = date
                }
                let key = PhotoSource.dayKey(for: day, calendar: calendar)
                planned += pickAcrossYears(found, limit: perDay).map { Planned(assetID: $0, day: key, created: created[$0]) }
            }
            return planned
        }
    }

    /// The same calendar day in each earlier year, skipping years where it doesn't exist (Feb 29).
    static func pastYearRanges(sameDayAs day: Date, earliestYear: Int = 1990, calendar: Calendar = .current) -> [DateInterval] {
        let target = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = target.year, let month = target.month, let dayOfMonth = target.day else { return [] }
        return stride(from: year - 1, through: earliestYear, by: -1).compactMap { pastYear in
            guard let start = calendar.date(from: DateComponents(year: pastYear, month: month, day: dayOfMonth)),
                  calendar.component(.day, from: start) == dayOfMonth,
                  let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    /// Up to `limit` photos, newest year first, taking one per year in turn so a single busy
    /// year doesn't crowd out the others.
    static func pickAcrossYears(_ photos: [(id: String, year: Int)], limit: Int) -> [String] {
        let years = Dictionary(grouping: photos, by: \.year).sorted { $0.key > $1.key }.map { $0.value.map(\.id) }
        var picked: [String] = []
        var round = 0
        while picked.count < limit, years.contains(where: { $0.count > round }) {
            for year in years where year.count > round && picked.count < limit {
                picked.append(year[round])
            }
            round += 1
        }
        return picked
    }

    /// The widget's photos in plan order: ones it already has keep their framing and captions,
    /// newly imported ones fill the gaps, and anything no longer planned drops out.
    static func assemble(_ plan: [Planned], existing: [WidgetPhoto], imported: [String: WidgetPhoto]) -> [WidgetPhoto] {
        let kept = Dictionary(existing.compactMap { photo in photo.assetID.map { ($0, photo) } }, uniquingKeysWith: { first, _ in first })
        return plan.compactMap { item in
            guard var photo = kept[item.assetID] ?? imported[item.assetID] else { return nil }
            photo.showOnDay = item.day
            return photo
        }
    }

    private static func imagesNewestFirst() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    // MARK: - Images

    /// The original image, downloading it from iCloud if needed.
    static func imageData(for assetID: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// A small square preview, for the album list.
    static func thumbnail(for assetID: String, side: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
