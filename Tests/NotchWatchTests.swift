// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum NotchWatchTests {
    static func run(_ suite: TestSuite) {
        readingContracts(suite)
        numberContracts(suite)
        changeContracts(suite)
        settleContracts(suite)
        matchContracts(suite)
        geometryContracts(suite)
        fingerprintContracts(suite)
        gateContracts(suite)
    }

    private static func readingContracts(_ suite: TestSuite) {
        suite.expect(NotchWatchSupport.headline(from: "Exporting video\n73 % complete") == "73%",
                     "a percentage anywhere in the area is its reading")
        suite.expect(NotchWatchSupport.headline(from: "  Build Succeeded \n") == "Build Succeeded",
                     "a short first line is shown as it is")
        suite.expect(NotchWatchSupport.headline(from: "Your order will arrive at the door at 14:30 today") == "14:30",
                     "a long line gives way to the clock in it")
        suite.expect(NotchWatchSupport.headline(from: "Uploading the whole project folder, 3.2 GB left") == "3.2 GB",
                     "or to the first amount with its unit")
        let long = NotchWatchSupport.headline(from: "Waiting for the other participants to join the call")
        suite.expect(long.count == NotchWatchSupport.headlineLength && long.hasSuffix("…"),
                     "text without numbers is cut to the strip's length")
        suite.expect(NotchWatchSupport.headline(from: " \n ").isEmpty, "an area without text has no reading")
        let area = "Project Alpha\nUploading 3 files\n12 MB of 40 MB"
        suite.expect(NotchWatchSupport.lines(in: area) == ["Project Alpha", "Uploading 3 files", "12 MB of 40 MB"]
                        && NotchWatchSupport.headline(from: area, line: 2) == "12 MB of 40 MB",
                     "a chosen line is what the island shows")
        suite.expect(NotchWatchSupport.headline(from: area, line: nil) == "Project Alpha"
                        && NotchWatchSupport.headline(from: "Done", line: 2) == "Done",
                     "without a choice, or once that line is gone, the reading is automatic again")
        suite.expect(NotchWatchSupport.normalized("  Concluído\n  AGORA ") == "concluido agora",
                     "comparisons ignore case, accents and spacing")
    }

    private static func numberContracts(_ suite: TestSuite) {
        let cases: [(String, Double?)] = [
            ("45%", 45), ("Progress 12,5 %", 12.5), ("1,234 of 5,000 files", 1234),
            ("1.234,5 MB", 1234.5), ("1,234.5 MB", 1234.5), ("Score -3", -3),
            ("3 of 10, then 80% done", 80), ("No numbers here", nil), ("1.234.567", 1234567),
        ]
        for (text, expected) in cases {
            suite.expect(NotchWatchSupport.number(in: text) == expected,
                         "\(text) reads as \(String(describing: expected))")
        }
    }

    private static func changeContracts(_ suite: TestSuite) {
        let now = Date()
        var tracker = NotchWatchTracker(condition: .changes)
        suite.expect(tracker.observe(signature: "uploading", reading: "Uploading", at: now) == nil,
                     "the first reading is the starting point")
        suite.expect(tracker.observe(signature: nil, reading: "Uploading", at: now) == nil,
                     "an unchanged picture is not a change")
        suite.expect(tracker.observe(signature: "uploadin", reading: "Uploadin", at: now) == nil,
                     "one different reading waits for the next to agree")
        suite.expect(tracker.observe(signature: "uploading", reading: "Uploading", at: now) == nil,
                     "a reading that flips back is noise, not a change")
        suite.expect(tracker.observe(signature: "done", reading: "Done", at: now) == nil
                        && tracker.observe(signature: "done", reading: "Done", at: now) == .changed,
                     "two readings in a row that agree on something new end the watch")
    }

    private static func settleContracts(_ suite: TestSuite) {
        let start = Date()
        var tracker = NotchWatchTracker(condition: .settles)
        _ = tracker.observe(signature: "line 1", reading: "line 1", at: start)
        suite.expect(tracker.observe(signature: nil, reading: "line 1",
                                     at: start.addingTimeInterval(120)) == nil,
                     "an area that never moved has not stopped anything")
        _ = tracker.observe(signature: "line 2", reading: "line 2", at: start.addingTimeInterval(121))
        suite.expect(tracker.observe(signature: nil, reading: "line 2",
                                     at: start.addingTimeInterval(140)) == nil,
                     "a short pause is not the end")
        suite.expect(tracker.observe(signature: "line 2", reading: "line 2",
                                     at: start.addingTimeInterval(121 + NotchWatchTracker.settleInterval)) == .settled,
                     "after a change, the settle interval of stillness ends the watch")
    }

    private static func matchContracts(_ suite: TestSuite) {
        let now = Date()
        var words = NotchWatchTracker(condition: .contains, text: "concluida")
        suite.expect(words.observe(signature: "x", reading: "Exportando…", at: now) == nil
                        && words.observe(signature: "y", reading: "Exportação CONCLUÍDA", at: now) == .shows("concluida"),
                     "the typed words are found whatever their case and accents")
        var empty = NotchWatchTracker(condition: .contains, text: "  ")
        suite.expect(!empty.isReady && empty.observe(signature: "x", reading: "anything", at: now) == nil,
                     "without words to find, nothing can match")
        var up = NotchWatchTracker(condition: .reaches, target: 100)
        suite.expect(up.observe(signature: "a", reading: "Copying 40%", at: now) == nil
                        && up.observe(signature: "b", reading: "Copying 99%", at: now) == nil
                        && up.observe(signature: "c", reading: "Copying 100%", at: now) == .reached("100%"),
                     "a number counting up reaches its target")
        var down = NotchWatchTracker(condition: .reaches, target: 0)
        suite.expect(down.observe(signature: "a", reading: "5 left", at: now) == nil
                        && down.observe(signature: "b", reading: "0 left", at: now) == .reached("0 left"),
                     "a number counting down reaches its target too")
        var already = NotchWatchTracker(condition: .reaches, target: 3)
        suite.expect(already.observe(signature: "a", reading: "3", at: now) == .reached("3"),
                     "a target already shown is met at once")
        var unread = NotchWatchTracker(condition: .reaches, target: 10)
        suite.expect(unread.observe(signature: "a", reading: "no digits", at: now) == nil && unread.start == nil,
                     "a reading without a number does not set the direction")
    }

    private static func geometryContracts(_ suite: TestSuite) {
        let windows: [(id: CGWindowID, bounds: CGRect)] = [
            (id: 7, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            (id: 3, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)),
        ]
        let front = NotchWatchSupport.windowCrop(for: CGRect(x: 150, y: 120, width: 100, height: 40), windows: windows)
        suite.expect(front?.id == 7 && front?.crop == CGRect(x: 50, y: 20, width: 100, height: 40),
                     "the front window under the area keeps it, in its own coordinates")
        let overhanging = NotchWatchSupport.windowCrop(for: CGRect(x: 420, y: 360, width: 100, height: 60), windows: windows)
        suite.expect(overhanging?.id == 7 && overhanging?.crop == CGRect(x: 320, y: 260, width: 80, height: 40),
                     "an area running past the window's edge is kept inside it")
        suite.expect(NotchWatchSupport.windowCrop(for: CGRect(x: 1200, y: 10, width: 50, height: 50), windows: windows) == nil,
                     "an area over no window has no window to follow")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 50, y: 20, width: 100, height: 40),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 800, height: 600))
                        == CGRect(x: 100, y: 40, width: 200, height: 80),
                     "points become the window image's pixels")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 350, y: 250, width: 100, height: 100),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 400, height: 300))
                        == CGRect(x: 350, y: 250, width: 50, height: 50),
                     "a window that shrank keeps what is left of the area")
        suite.expect(NotchWatchSupport.pixelCrop(CGRect(x: 500, y: 500, width: 10, height: 10),
                                                 windowSize: CGSize(width: 400, height: 300),
                                                 imageSize: CGSize(width: 400, height: 300)) == nil,
                     "an area the window no longer covers reads nothing")
    }

    private static func fingerprintContracts(_ suite: TestSuite) {
        func image(_ fill: (CGContext) -> Void) -> CGImage? {
            guard let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            fill(context)
            return context.makeImage()
        }
        let empty = image { $0.setFillColor(gray: 0.1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 32)) }
        let half = image {
            $0.setFillColor(gray: 0.1, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
            $0.setFillColor(gray: 0.9, alpha: 1); $0.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        let a = empty.flatMap(NotchWatchSupport.fingerprint)
        let b = empty.flatMap(NotchWatchSupport.fingerprint)
        let c = half.flatMap(NotchWatchSupport.fingerprint)
        suite.expect(a != nil && NotchWatchSupport.sameFingerprint(a, b), "the same picture reads the same")
        suite.expect(!NotchWatchSupport.sameFingerprint(a, c), "a progress bar that moved reads as a change")
        suite.expect(NotchWatchSupport.signature(text: "  Done ", fingerprint: c) == "done"
                        && NotchWatchSupport.signature(text: "", fingerprint: c)?.hasPrefix("image:") == true,
                     "text decides when there is any, the picture otherwise")
    }

    private static func gateContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-watch"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults), "Watch needs the island")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchWatchSupport.isEnabled(in: defaults) && NotchSupport.routes(.watch, in: defaults)
                        && NotchSupport.modules(in: defaults).contains(.watch),
                     "with the island on, the page and its alerts are there by default")
        suite.expect(NotchWatchCondition.saved(in: defaults) == .changes, "a first watch speaks up on any change")
        defaults.set("settles", forKey: DefaultsKey.notchWatchCondition)
        suite.expect(NotchWatchCondition.saved(in: defaults) == .settles, "the last rule chosen is kept")
        defaults.set("watch", forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults) && !NotchSupport.routes(.watch, in: defaults),
                     "a hidden page stops watching")
        defaults.set("", forKey: DefaultsKey.notchHiddenModules)
        defaults.set(false, forKey: DefaultsKey.notchWatchEnabled)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults) && !NotchSupport.modules(in: defaults).contains(.watch),
                     "its own switch removes the page")
        defaults.set(true, forKey: DefaultsKey.notchWatchEnabled)
        defaults.set(false, forKey: AppFeature.notchWatch.availabilityKey)
        suite.expect(!NotchWatchSupport.isEnabled(in: defaults), "uninstalling the feature turns it off")
        suite.expect(NotchSupport.compactActivities(timer: true, watch: true, downloads: true, agents: false,
                                                    calendar: false, music: true) == [.timer, .watch, .downloads, .music],
                     "a watch follows the timer in the closed island's automatic order")
        suite.expect(AppFeature.notchWatch.permissions == [.screenRecording],
                     "reading the area is the only permission Watch asks for")
    }
}
