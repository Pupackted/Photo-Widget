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

    @Test func shuffleShowsEveryPhotoOncePerCycle() {
        let config = widget(photos: 7, rotation: .hourly, order: .shuffle)
        // Walk slot by slot, using the tap offset as the step counter.
        for cycle in 0..<5 {
            let seen = (0..<7).map { PhotoSchedule.index(for: config, at: Date(timeIntervalSince1970: 0), offset: cycle * 7 + $0) }
            #expect(Set(seen).count == 7)
        }
    }

    @Test func shuffleNeverRepeatsAcrossCycleBoundary() {
        let config = widget(photos: 5, rotation: .hourly, order: .shuffle)
        let base = Date(timeIntervalSince1970: 0)
        let sequence = (0..<200).map { PhotoSchedule.index(for: config, at: base, offset: $0) }
        #expect(zip(sequence, sequence.dropFirst()).allSatisfy { $0 != $1 })
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

    @Test func hsbRoundTrips() {
        let color = RGBColor(red: 0.8, green: 0.35, blue: 0.2)
        let hsb = color.hsb
        let back = RGBColor(hue: hsb.hue, saturation: hsb.saturation, brightness: hsb.brightness)
        #expect(abs(back.red - color.red) < 0.001)
        #expect(abs(back.green - color.green) < 0.001)
        #expect(abs(back.blue - color.blue) < 0.001)
    }
}
