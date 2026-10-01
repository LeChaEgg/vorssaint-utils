// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// What a watched area has to do before the island speaks up.
enum NotchWatchCondition: String, CaseIterable, Identifiable {
    /// Its text changes, or its picture when it holds no text.
    case changes
    /// It changed at least once and then held still, as a log or a progress
    /// bar does when the work behind it ends.
    case settles
    /// It shows the text the person typed, such as "Done".
    case contains
    /// Its number reaches the one the person typed, counting up or down.
    case reaches

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .changes: return "arrow.triangle.2.circlepath"
        case .settles: return "pause.circle"
        case .contains: return "text.magnifyingglass"
        case .reaches: return "flag.checkered"
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> NotchWatchCondition {
        NotchWatchCondition(rawValue: defaults.string(forKey: DefaultsKey.notchWatchCondition) ?? "") ?? .changes
    }
}

/// Why a watch ended.
enum NotchWatchOutcome: Equatable {
    case changed
    case settled
    case shows(String)
    case reached(String)
    case closed
}

/// Follows one area reading after reading and decides when its condition
/// is met. Readings arrive only when the area's pixels move; `observe(nil)`
/// says the area looks as it did, so a quiet area can still settle.
struct NotchWatchTracker {
    static let settleInterval: TimeInterval = 30

    let condition: NotchWatchCondition
    let text: String
    let target: Double?

    private(set) var baseline: String?
    private(set) var pending: String?
    private(set) var current: String?
    private(set) var lastChange: Date?
    private(set) var sawChange = false
    private(set) var start: Double?

    init(condition: NotchWatchCondition, text: String = "", target: Double? = nil) {
        self.condition = condition
        self.text = text
        self.target = target
    }

    /// Whether the rule can be met at all: a text to find or a number to
    /// reach must have been typed.
    var isReady: Bool {
        switch condition {
        case .changes, .settles: return true
        case .contains: return !NotchWatchSupport.normalized(text).isEmpty
        case .reaches: return target != nil
        }
    }

    /// `signature` compares two readings: the area's normalized text, or a
    /// coarse picture of it when it holds no text. `reading` is the text as
    /// read, for finding words and numbers.
    mutating func observe(signature: String?, reading: String, at date: Date) -> NotchWatchOutcome? {
        guard isReady else { return nil }
        switch condition {
        case .changes:
            guard let signature else { return nil }
            guard let baseline else { self.baseline = signature; return nil }
            guard signature != baseline else { pending = nil; return nil }
            // A change counts once two readings in a row agree on it, so a
            // frame caught halfway through redrawing does not end the watch.
            if pending == signature { return .changed }
            pending = signature
            return nil
        case .settles:
            if let signature, signature != current {
                if current != nil { sawChange = true }
                current = signature
                lastChange = date
                return nil
            }
            guard sawChange, let lastChange, date.timeIntervalSince(lastChange) >= Self.settleInterval else { return nil }
            return .settled
        case .contains:
            let wanted = NotchWatchSupport.normalized(text)
            return NotchWatchSupport.normalized(reading).contains(wanted) ? .shows(text) : nil
        case .reaches:
            guard let target, let value = NotchWatchSupport.number(in: reading) else { return nil }
            let shown = NotchWatchSupport.headline(from: reading)
            guard let start else {
                self.start = value
                return value == target ? .reached(shown) : nil
            }
            if start < target, value >= target { return .reached(shown) }
            if start > target, value <= target { return .reached(shown) }
            return nil
        }
    }
}

enum NotchWatchSupport {
    /// How often the area is read: often while its page is open, so the
    /// preview feels live, and less while it only feeds the closed island.
    static let visibleInterval: TimeInterval = 1
    static let backgroundInterval: TimeInterval = 2
    /// Text recognition gets slower with size and gains nothing past this.
    static let maximumRecognitionSide = 900
    static let headlineLength = 22
    static let stripWingRange: ClosedRange<CGFloat> = 56...150
    /// An area without text shows itself, this wide, where its reading would be.
    static let thumbnailWidth: CGFloat = 40

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchWatch.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchWatchEnabled)
            && NotchSupport.modules(in: defaults).contains(.watch)
    }

    /// For comparing and finding words: no case, accents or extra spaces.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// The part of the text worth showing beside the camera: a percentage
    /// first, then a short first line as it is, then a clock or a number
    /// with its unit, and otherwise the first line cut short.
    static func headline(from text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        let joined = lines.joined(separator: " ")
        if let percent = firstMatch(percentPattern, in: joined) {
            return percent.replacingOccurrences(of: " ", with: "")
        }
        if first.count <= headlineLength { return first }
        if let clock = firstMatch(clockPattern, in: joined) { return clock }
        if let amount = firstMatch(amountPattern, in: joined) { return amount }
        return String(first.prefix(headlineLength - 1)) + "…"
    }

    /// The area's lines, top to bottom, as a person can pick one of them.
    static func lines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The line the person chose to show, cut to the strip's length, or the
    /// automatic reading while that line is missing.
    static func headline(from text: String, line: Int?) -> String {
        let lines = lines(in: text)
        guard let line, lines.indices.contains(line) else { return headline(from: text) }
        let chosen = lines[line]
        return chosen.count <= headlineLength ? chosen : String(chosen.prefix(headlineLength - 1)) + "…"
    }

    /// The number a "reaches" rule compares: a percentage first, otherwise
    /// the first number in the text. Both decimal marks are understood.
    static func number(in text: String) -> Double? {
        let source = firstMatch(percentPattern, in: text) ?? text
        guard let raw = firstMatch(numberPattern, in: source) else { return nil }
        return parse(raw)
    }

    static func parse(_ raw: String) -> Double? {
        var digits = raw.replacingOccurrences(of: " ", with: "")
        let negative = digits.hasPrefix("-") || digits.hasPrefix("−")
        digits = digits.trimmingCharacters(in: CharacterSet(charactersIn: "+-−"))
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            // The later mark separates the decimals; the other groups thousands.
            if dot > comma {
                digits = digits.replacingOccurrences(of: ",", with: "")
            } else {
                digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            }
        case (nil, _?):
            let groups = digits.split(separator: ",", omittingEmptySubsequences: false)
            // 1,234 groups thousands; 12,5 has a decimal comma.
            digits = groups.count > 2 || groups.last?.count == 3
                ? digits.replacingOccurrences(of: ",", with: "")
                : digits.replacingOccurrences(of: ",", with: ".")
        case (_?, nil):
            if digits.split(separator: ".").count > 2 { digits = digits.replacingOccurrences(of: ".", with: "") }
        case (nil, nil):
            break
        }
        guard let value = Double(digits), value.isFinite else { return nil }
        return negative ? -value : value
    }

    static func formatted(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    /// The area as a 16 × 16 grid of coarse grey levels: small enough that
    /// antialiasing and compression noise read the same, sharp enough that
    /// a moving bar, a new line or a changed colour do not.
    static func fingerprint(_ image: CGImage) -> [UInt8]? {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels.map { $0 / 16 } : nil
    }

    /// Whether two fingerprints show the same picture, allowing a few cells
    /// to cross one grey level, as a blinking caret or a shadow does.
    static func sameFingerprint(_ lhs: [UInt8]?, _ rhs: [UInt8]?) -> Bool {
        guard let lhs, let rhs, lhs.count == rhs.count else { return false }
        let moved = zip(lhs, rhs).filter { abs(Int($0) - Int($1)) > 1 }.count
        let nudged = zip(lhs, rhs).filter { $0 != $1 }.count
        return moved == 0 && nudged <= 3
    }

    static func signature(text: String, fingerprint: [UInt8]?) -> String? {
        let normalized = normalized(text)
        if !normalized.isEmpty { return normalized }
        return fingerprint.map { "image:" + $0.map(String.init).joined(separator: ".") }
    }

    /// The part of a window's image `crop` covers, `crop` being in points
    /// from the window's top-left corner and `windowSize` the window's size
    /// in points. Nil when the area left the window.
    static func pixelCrop(_ crop: CGRect, windowSize: CGSize, imageSize: CGSize) -> CGRect? {
        guard windowSize.width > 0, windowSize.height > 0 else { return nil }
        let scaleX = imageSize.width / windowSize.width
        let scaleY = imageSize.height / windowSize.height
        let rect = CGRect(x: crop.minX * scaleX, y: crop.minY * scaleY,
                          width: crop.width * scaleX, height: crop.height * scaleY).integral
            .intersection(CGRect(origin: .zero, size: imageSize))
        return rect.isNull || rect.width < 4 || rect.height < 4 ? nil : rect
    }

    /// The window under the middle of a dragged area, front to back, and the
    /// area in points from that window's top-left corner, kept inside it.
    static func windowCrop(for area: CGRect, windows: [(id: CGWindowID, bounds: CGRect)])
        -> (id: CGWindowID, crop: CGRect)? {
        let middle = CGPoint(x: area.midX, y: area.midY)
        guard let window = windows.first(where: { $0.bounds.contains(middle) }) else { return nil }
        let inside = area.intersection(window.bounds)
        guard !inside.isNull, inside.width >= 8, inside.height >= 8 else { return nil }
        return (window.id, inside.offsetBy(dx: -window.bounds.minX, dy: -window.bounds.minY))
    }

    private static let percentPattern = #"[-+]?\d{1,3}(?:[.,]\d+)?\s?%"#
    private static let clockPattern = #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#
    private static let amountPattern = #"[-+]?\d[\d.,]*(?:\s?[A-Za-z]{1,3}\b)?"#
    private static let numberPattern = #"[-+−]?\d[\d.,]*\d|[-+−]?\d"#

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
}
