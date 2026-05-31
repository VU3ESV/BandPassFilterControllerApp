import Foundation

/// Yaesu-standard BCD band encoding used by the firmware.
/// Codes 1–10 map to the 10 HF / 6 m bands. Code 0 (and out-of-band) means bypass.
enum Band: Int, CaseIterable, Identifiable {
    case bypass = 0
    case m160 = 1
    case m80 = 2
    case m40 = 3
    case m30 = 4
    case m20 = 5
    case m17 = 6
    case m15 = 7
    case m12 = 8
    case m10 = 9
    case m6 = 10

    var id: Int { rawValue }

    /// Short label shown on the filter cards.
    var label: String {
        switch self {
        case .bypass: return "BYP"
        case .m160: return "160m"
        case .m80: return "80m"
        case .m40: return "40m"
        case .m30: return "30m"
        case .m20: return "20m"
        case .m17: return "17m"
        case .m15: return "15m"
        case .m12: return "12m"
        case .m10: return "10m"
        case .m6: return "6m"
        }
    }

    /// Nominal band edge used purely for display ordering / context.
    var nominalMHz: String {
        switch self {
        case .bypass: return "—"
        case .m160: return "1.8"
        case .m80: return "3.5"
        case .m40: return "7.0"
        case .m30: return "10.1"
        case .m20: return "14.0"
        case .m17: return "18.0"
        case .m15: return "21.0"
        case .m12: return "24.8"
        case .m10: return "28.0"
        case .m6: return "50.0"
        }
    }

    /// True when the firmware would route the signal straight through (no filter section).
    var isBypass: Bool { self == .bypass }

    /// Resolve a band from the firmware's `band` field, which may arrive as a BCD
    /// integer code or as a textual label such as "20m" / "bypass".
    static func resolve(from value: BandValue?) -> Band {
        guard let value else { return .bypass }
        switch value {
        case .code(let code):
            return Band(rawValue: code) ?? .bypass
        case .name(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if trimmed.isEmpty || trimmed == "bypass" || trimmed == "byp" || trimmed == "oob" {
                return .bypass
            }
            // Match "20m", "20", "20 m"
            let digits = trimmed.replacingOccurrences(of: "m", with: "")
                .trimmingCharacters(in: .whitespaces)
            return Band.allCases.first { $0.label.lowercased() == trimmed }
                ?? Band.allCases.first { $0.label.lowercased() == "\(digits)m" }
                ?? .bypass
        }
    }
}

/// The `band` field in the status JSON can be either a number or a string,
/// so decode it tolerantly.
enum BandValue: Decodable {
    case code(Int)
    case name(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .code(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            // A numeric string still counts as a code.
            if let asInt = Int(stringValue.trimmingCharacters(in: .whitespaces)) {
                self = .code(asInt)
            } else {
                self = .name(stringValue)
            }
        } else {
            self = .name("")
        }
    }
}
