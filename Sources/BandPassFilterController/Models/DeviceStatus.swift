import Foundation

/// Per-radio TCI state, mirrored from the firmware's `r1` / `r2` status objects.
struct RadioStatus: Decodable, Equatable {
    var connected: Bool
    var freqHz: Int
    var band: Band
    var tuning: Bool

    enum CodingKeys: String, CodingKey {
        case connected
        case freqHz = "freq_hz"
        case band
        case tuning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        connected = (try? c.decode(Bool.self, forKey: .connected)) ?? false
        freqHz = (try? c.decode(Int.self, forKey: .freqHz)) ?? 0
        tuning = (try? c.decode(Bool.self, forKey: .tuning)) ?? false
        band = Band.resolve(from: try? c.decode(BandValue.self, forKey: .band))
    }

    init(connected: Bool, freqHz: Int, band: Band, tuning: Bool) {
        self.connected = connected
        self.freqHz = freqHz
        self.band = band
        self.tuning = tuning
    }

    /// Human readable frequency such as "14.074 MHz".
    var frequencyDisplay: String {
        guard freqHz > 0 else { return "—" }
        let mhz = Double(freqHz) / 1_000_000.0
        return String(format: "%.3f MHz", mhz)
    }

    /// Coarse activity state shown as a pill on the card.
    enum Activity: String {
        case tuning = "TUNE"
        case receiving = "RX"
        case offline = "OFF"
    }

    var activity: Activity {
        if !connected { return .offline }
        if tuning { return .tuning }
        return .receiving
    }
}

/// Full device snapshot returned by `GET /status`.
struct DeviceStatus: Decodable, Equatable {
    var filter: String?
    var mode: String          // "shared" | "dual"
    var apMode: Bool
    var wifiState: String     // "up" | "down"
    var ip: String?
    var rssi: Int?
    var r1: RadioStatus
    var r2: RadioStatus
    var uptimeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case filter
        case mode
        case apMode = "ap_mode"
        case wifi
        case ip
        case rssi
        case r1
        case r2
        case uptimeSeconds = "uptime_s"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filter = try? c.decode(String.self, forKey: .filter)
        mode = (try? c.decode(String.self, forKey: .mode)) ?? "dual"
        apMode = (try? c.decode(Bool.self, forKey: .apMode)) ?? false
        wifiState = (try? c.decode(String.self, forKey: .wifi)) ?? "down"
        ip = try? c.decode(String.self, forKey: .ip)
        rssi = try? c.decode(Int.self, forKey: .rssi)
        r1 = (try? c.decode(RadioStatus.self, forKey: .r1))
            ?? RadioStatus(connected: false, freqHz: 0, band: .bypass, tuning: false)
        r2 = (try? c.decode(RadioStatus.self, forKey: .r2))
            ?? RadioStatus(connected: false, freqHz: 0, band: .bypass, tuning: false)
        uptimeSeconds = (try? c.decode(Int.self, forKey: .uptimeSeconds)) ?? 0
    }

    var isSharedMode: Bool { mode.lowercased() == "shared" }

    var wifiUp: Bool { wifiState.lowercased() == "up" }

    var uptimeDisplay: String {
        let s = uptimeSeconds
        let days = s / 86400
        let hours = (s % 86400) / 3600
        let minutes = (s % 3600) / 60
        let seconds = s % 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }
}
