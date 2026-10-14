//
//  Photo_WidgetTests.swift
//  Photo WidgetTests
//
//  Created by Adrian Yusufa Rachman on 05/06/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Photo_Widget

struct PhotoScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return calendar
    }()

    private func widget(photos: Int, rotation: RotationInterval, order: PlaybackOrder = .inOrder) -> PhotoWidgetConfig {
        var widget = PhotoWidgetConfig(name: "Test")
        widget.photos = (0..<photos).map { _ in WidgetPhoto(pixelWidth: 400, pixelHeight: 300) }
        widget.rotation = rotation
        widget.order = order
        return widget
    }

    @Test func neverRotatingStaysOnCoverUntilTapped() {
        let config = widget(photos: 4, rotation: .never)
        #expect(PhotoSchedule.index(for: config, at: .now) == 0)
        #expect(PhotoSchedule.index(for: config, at: .now.addingTimeInterval(86_400 * 3)) == 0)
        #expect(PhotoSchedule.index(for: config, at: .now, offset: 5) == 1)
    }

    @Test func hourlyChangesOnTheHour() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 59)))
        let next = try #require(PhotoSchedule.nextChange(after: start, interval: .hourly, calendar: calendar))
        #expect(calendar.component(.hour, from: next) == 10)
        #expect(calendar.component(.minute, from: next) == 0)
    }

    @Test func dailyChangesAtLocalMidnight() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 23, minute: 30)))
        let next = try #require(PhotoSchedule.nextChange(after: start, interval: .daily, calendar: calendar))
        #expect(calendar.dateComponents([.day, .hour, .minute], from: next) == DateComponents(day: 21, hour: 0, minute: 0))
    }

    @Test func entryDatesStartNowAndAreAscending() {
        let dates = PhotoSchedule.entryDates(from: .now, interval: .fifteenMinutes, limit: 10)
        #expect(dates.count == 10)
        #expect(dates.first == .now || abs(dates[0].timeIntervalSinceNow) < 1)
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })
    }

    /// A date whose hourly slot is a multiple of `count`, in whatever time zone the tests run in.
    private func cycleAlignedDate(count: Int) -> Date {
        var date = Date(timeIntervalSince1970: 0)
        while PhotoSchedule.slot(at: date, interval: .hourly) % count != 0 { date += 3600 }
        return date
    }

    @Test func shuffleShowsEveryPhotoOncePerCycle() {
        let config = widget(photos: 7, rotation: .hourly, order: .shuffle)
        let base = cycleAlignedDate(count: 7)
        // Walk slot by slot, using the tap offset as the step counter.
        for cycle in 0..<5 {
            let seen = (0..<7).map { PhotoSchedule.index(for: config, at: base, offset: cycle * 7 + $0) }
            #expect(Set(seen).count == 7)
        }
    }

    @Test func shuffleNeverRepeatsAcrossCycleBoundary() {
        for count in 2...6 {
            let config = widget(photos: count, rotation: .hourly, order: .shuffle)
            let base = Date(timeIntervalSince1970: 0)
            let sequence = (0..<200).map { PhotoSchedule.index(for: config, at: base, offset: $0) }
            #expect(zip(sequence, sequence.dropFirst()).allSatisfy { $0 != $1 }, "\(count) photos")
        }
    }

    @Test func neverRotatingShuffleStillStartsOnCover() {
        let config = widget(photos: 5, rotation: .never, order: .shuffle)
        #expect(PhotoSchedule.index(for: config, at: .now) == 0)
    }

    @Test func collagePagesNeverRepeatAPhoto() {
        for layout in [CollageLayout.duo, .quad] {
            for count in 1...9 {
                for order in PlaybackOrder.allCases {
                    var config = widget(photos: count, rotation: .hourly, order: order)
                    config.style.layout = layout
                    let cells = config.effectiveLayout.cellCount
                    for offset in 0..<40 {
                        let page = PhotoSchedule.indices(for: config, at: .now, offset: offset)
                        #expect(page.count == cells)
                        #expect(Set(page).count == page.count)
                    }
                }
            }
        }
    }

    @Test func collageShrinksToThePhotosThereAre() {
        #expect(CollageLayout.quad.effective(photoCount: 3) == .duo)
        #expect(CollageLayout.quad.effective(photoCount: 1) == .single)
        #expect(CollageLayout.duo.effective(photoCount: 2) == .duo)
        #expect(CollageLayout.single.effective(photoCount: 9) == .single)
    }

    @Test func dayCountingCaptionsRefreshAtMidnight() throws {
        var config = widget(photos: 1, rotation: .never)
        config.style.caption = .timeAgo
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 15)))
        let dates = PhotoSchedule.timelineDates(for: config, from: start, calendar: calendar)
        #expect(dates.count == 8)
        #expect(dates.dropFirst().allSatisfy { calendar.component(.hour, from: $0) == 0 })

        config.style.caption = .none
        #expect(PhotoSchedule.timelineDates(for: config, from: start, calendar: calendar) == [start])
    }
}

struct CaptionTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func dayCounterCountsBothWays() throws {
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 9)))
        let past = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5)))
        let future = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 27)))
        #expect(WidgetAppearance.counterText(to: past, label: "together", on: today, calendar: calendar) == "10 days together")
        #expect(WidgetAppearance.counterText(to: future, label: "Bali", on: today, calendar: calendar) == "12 days until Bali")
        #expect(WidgetAppearance.counterText(to: future, label: " ", on: today, calendar: calendar) == "12 days to go")
        #expect(WidgetAppearance.counterText(to: today, label: "", on: today, calendar: calendar) == "Today")
    }

    @Test func perPhotoCaptionsComeFromThePhoto() {
        var style = WidgetStyle()
        style.caption = .perPhoto
        var photo = WidgetPhoto(pixelWidth: 10, pixelHeight: 10)
        #expect(WidgetAppearance.captionText(style: style, photo: photo, size: .small, date: .now) == nil)
        photo.caption = "Bali, 2019"
        #expect(WidgetAppearance.captionText(style: style, photo: photo, size: .small, date: .now) == "Bali, 2019")
    }
}

struct CropStateTests {
    @Test func clampedCropStaysInsideImage() {
        let crop = CropState(centerX: 0.02, centerY: 0.98, zoom: 2)
            .clamped(imageAspect: 4.0 / 3.0, targetAspect: 1)
        let rect = crop.rect(imageAspect: 4.0 / 3.0, targetAspect: 1)
        #expect(rect.minX >= -0.0001 && rect.maxX <= 1.0001)
        #expect(rect.minY >= -0.0001 && rect.maxY <= 1.0001)
    }

    @Test func zoomIsLimited() {
        #expect(CropState(centerX: 0.5, centerY: 0.5, zoom: 0.3).clamped(imageAspect: 1, targetAspect: 1).zoom == CropState.minZoom)
        #expect(CropState(centerX: 0.5, centerY: 0.5, zoom: 40).clamped(imageAspect: 1, targetAspect: 1).zoom == CropState.maxZoom)
    }

    @Test func cropMatchesTargetAspectInPixels() {
        let imageAspect = 3.0 / 2.0
        for target in [1.0, 364.0 / 170.0, 364.0 / 382.0] {
            let rect = CropState(centerX: 0.5, centerY: 0.5, zoom: 1.7).rect(imageAspect: imageAspect, targetAspect: target)
            let pixelAspect = (rect.width * imageAspect) / rect.height
            #expect(abs(pixelAspect - target) < 0.0001)
        }
    }

    @Test func frameLayoutsKeepPhotoInsideWidget() {
        for size in WidgetSize.allCases {
            for frame in FrameStyle.allCases {
                let layout = WidgetLayout.canonical(size, frame: frame)
                #expect(layout.photoRect.minX >= 0 && layout.photoRect.maxX <= size.canonicalSize.width)
                #expect(layout.photoRect.minY >= 0 && layout.photoRect.maxY <= size.canonicalSize.height)
            }
        }
    }

    @Test func collageCellsTileThePhotoAreaWithoutOverlapping() {
        for size in WidgetSize.allCases {
            for frame in FrameStyle.allCases {
                for collage in CollageLayout.allCases {
                    let layout = WidgetLayout.canonical(size, frame: frame, collage: collage)
                    let area = CGRect(origin: .zero, size: layout.photoRect.size)
                    #expect(layout.cells.count == collage.cellCount)
                    for (i, cell) in layout.cells.enumerated() {
                        #expect(area.insetBy(dx: -0.001, dy: -0.001).contains(cell))
                        // Every cell has the same shape, so one render fits any of them.
                        #expect(abs(cell.width / cell.height - layout.photoAspect) < 0.0001)
                        for other in layout.cells[(i + 1)...] {
                            #expect(!cell.intersects(other))
                        }
                    }
                }
            }
        }
    }
}

struct ModelTests {
    @Test func configRoundTripsThroughJSON() throws {
        var widget = PhotoWidgetConfig(name: "Round trip")
        var photo = WidgetPhoto(pixelWidth: 1200, pixelHeight: 800)
        photo.crops[WidgetSize.medium.rawValue] = CropState(centerX: 0.3, centerY: 0.6, zoom: 1.4)
        widget.photos = [photo]
        widget.style.filter = .film
        widget.style.frame = .polaroid

        let decoded = try JSONDecoder().decode(PhotoWidgetConfig.self, from: JSONEncoder().encode(widget))
        #expect(decoded == widget)
    }

    @Test func olderLibrariesStillLoad() throws {
        // A widget saved before collages, counters and per-photo captions existed.
        let json = """
        {"id":"7E1C2D4A-0B5B-4C55-9D87-4D2F0E1A2B3C","name":"Summer","rotation":"hourly","order":"inOrder",
         "tapAction":"openApp","createdAt":0,"modifiedAt":0,
         "style":{"filter":"film","filterIntensity":1,"frame":"border","mat":"auto","caption":"none","captionText":"","font":"rounded","fullColorInTintedMode":true},
         "photos":[{"id":"1E1C2D4A-0B5B-4C55-9D87-4D2F0E1A2B3C","pixelWidth":400,"pixelHeight":300,"focus":{"x":0.5,"y":0.5},"crops":{},
                    "averageColor":{"red":0.1,"green":0.2,"blue":0.3}}]}
        """
        let widget = try JSONDecoder().decode(PhotoWidgetConfig.self, from: Data(json.utf8))
        #expect(widget.name == "Summer")
        #expect(widget.style.filter == .film)
        #expect(widget.style.layout == .single)
        #expect(widget.photos.count == 1)
        #expect(widget.photos[0].caption.isEmpty)
    }

    @Test func unknownValuesFallBackInsteadOfFailing() throws {
        // As if written by a newer version with a filter this one doesn't know.
        let json = """
        {"id":"7E1C2D4A-0B5B-4C55-9D87-4D2F0E1A2B3C","name":"Future","rotation":"weekly",
         "style":{"filter":"sparkle","frame":"border"},
         "photos":[{"id":"1E1C2D4A-0B5B-4C55-9D87-4D2F0E1A2B3C","pixelWidth":400,"pixelHeight":300},{"broken":true}]}
        """
        let widget = try JSONDecoder().decode(PhotoWidgetConfig.self, from: Data(json.utf8))
        #expect(widget.rotation == .hourly)
        #expect(widget.style.filter == .original)
        #expect(widget.style.frame == .border)
        #expect(widget.photos.count == 1)
    }

    @Test func defaultWidgetIsStable() {
        var first = PhotoWidgetConfig(name: "First")
        first.createdAt = Date(timeIntervalSince1970: 100)
        first.photos = [WidgetPhoto(pixelWidth: 1, pixelHeight: 1)]
        var empty = PhotoWidgetConfig(name: "Empty")
        empty.createdAt = Date(timeIntervalSince1970: 50)
        var later = PhotoWidgetConfig(name: "Later")
        later.createdAt = Date(timeIntervalSince1970: 200)
        later.modifiedAt = .now
        later.photos = [WidgetPhoto(pixelWidth: 1, pixelHeight: 1)]

        let widgets = [empty, later, first]
        #expect(WidgetStorage.defaultWidget(in: widgets)?.id == first.id)
        // A deleted or missing choice falls back to the default rather than going blank.
        #expect(WidgetStorage.resolve(UUID(), in: widgets)?.id == first.id)
        #expect(WidgetStorage.resolve(later.id, in: widgets)?.id == later.id)
    }

    @Test func hsbRoundTrips() {
        let color = RGBColor(red: 0.8, green: 0.35, blue: 0.2)
        let hsb = color.hsb
        let back = RGBColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
        #expect(abs(back.red - color.red) < 0.001)
        #expect(abs(back.green - color.green) < 0.001)
        #expect(abs(back.blue - color.blue) < 0.001)
    }
}
