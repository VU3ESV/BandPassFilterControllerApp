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

/// RF detector readings (firmware `sensors` object): forward/reverse detector
/// voltage in millivolts for each filter. 0 when no RF / no detector fitted.
struct Sensors: Decodable, Equatable {
    var bpf1FwdMv: Int = 0
    var bpf1RevMv: Int = 0
    var bpf2FwdMv: Int = 0
    var bpf2RevMv: Int = 0

    enum CodingKeys: String, CodingKey {
        case bpf1FwdMv = "bpf1_fwd_mv"
        case bpf1RevMv = "bpf1_rev_mv"
        case bpf2FwdMv = "bpf2_fwd_mv"
        case bpf2RevMv = "bpf2_rev_mv"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bpf1FwdMv = (try? c.decode(Int.self, forKey: .bpf1FwdMv)) ?? 0
        bpf1RevMv = (try? c.decode(Int.self, forKey: .bpf1RevMv)) ?? 0
        bpf2FwdMv = (try? c.decode(Int.self, forKey: .bpf2FwdMv)) ?? 0
        bpf2RevMv = (try? c.decode(Int.self, forKey: .bpf2RevMv)) ?? 0
    }

    func forward(_ bpf: Int) -> Int { bpf == 1 ? bpf1FwdMv : bpf2FwdMv }
    func reverse(_ bpf: Int) -> Int { bpf == 1 ? bpf1RevMv : bpf2RevMv }
}

/// A single band-change event from the firmware `history` ring buffer.
struct BandEvent: Decodable, Equatable {
    var uptimeSeconds: Int   // `t`: device uptime when the event happened
    var bpf: Int
    var freqHz: Int
    var code: Int
    var inhibit: Bool        // `inh`: forced to bypass
    var tune: Bool

    enum CodingKeys: String, CodingKey {
        case t, bpf, hz, code, inh, tune
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uptimeSeconds = (try? c.decode(Int.self, forKey: .t)) ?? 0
        bpf = (try? c.decode(Int.self, forKey: .bpf)) ?? 0
        freqHz = (try? c.decode(Int.self, forKey: .hz)) ?? 0
        code = (try? c.decode(Int.self, forKey: .code)) ?? 0
        inhibit = (try? c.decode(Bool.self, forKey: .inh)) ?? false
        tune = (try? c.decode(Bool.self, forKey: .tune)) ?? false
    }

    var band: Band { inhibit ? .bypass : (Band(rawValue: code) ?? .bypass) }

    var frequencyDisplay: String {
        guard freqHz > 0 else { return "—" }
        return String(format: "%.3f MHz", Double(freqHz) / 1_000_000.0)
    }
}

/// Full device snapshot returned by `GET /status`.
struct DeviceStatus: Decodable, Equatable {
    var filter: String?
    var version: String?      // firmware version, e.g. "0.5.0"
    var build: String?        // firmware build stamp
    var mode: String          // "shared" | "dual"
    var apMode: Bool
    var wifiState: String     // "up" | "down"
    var ip: String?
    var rssi: Int?
    var r1: RadioStatus
    var r2: RadioStatus
    var sensors: Sensors
    var history: [BandEvent]
    var historyCount: Int
    var uptimeSeconds: Int

    enum CodingKeys: String, CodingKey {
        case filter
        case version
        case build
        case mode
        case apMode = "ap_mode"
        case wifi
        case ip
        case rssi
        case r1
        case r2
        case sensors
        case history
        case historyCount = "history_count"
        case uptimeSeconds = "uptime_s"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filter = try? c.decode(String.self, forKey: .filter)
        version = try? c.decode(String.self, forKey: .version)
        build = try? c.decode(String.self, forKey: .build)
        mode = (try? c.decode(String.self, forKey: .mode)) ?? "dual"
        apMode = (try? c.decode(Bool.self, forKey: .apMode)) ?? false
        wifiState = (try? c.decode(String.self, forKey: .wifi)) ?? "down"
        ip = try? c.decode(String.self, forKey: .ip)
        rssi = try? c.decode(Int.self, forKey: .rssi)
        r1 = (try? c.decode(RadioStatus.self, forKey: .r1))
            ?? RadioStatus(connected: false, freqHz: 0, band: .bypass, tuning: false)
        r2 = (try? c.decode(RadioStatus.self, forKey: .r2))
            ?? RadioStatus(connected: false, freqHz: 0, band: .bypass, tuning: false)
        sensors = (try? c.decode(Sensors.self, forKey: .sensors)) ?? Sensors()
        history = (try? c.decode([BandEvent].self, forKey: .history)) ?? []
        historyCount = (try? c.decode(Int.self, forKey: .historyCount)) ?? history.count
        uptimeSeconds = (try? c.decode(Int.self, forKey: .uptimeSeconds)) ?? 0
    }

    var isSharedMode: Bool { mode.lowercased() == "shared" }

    /// True when the firmware reports any RF detector hardware / signal.
    var hasSensorData: Bool {
        sensors.bpf1FwdMv > 0 || sensors.bpf1RevMv > 0 ||
        sensors.bpf2FwdMv > 0 || sensors.bpf2RevMv > 0
    }

    var firmwareDisplay: String {
        guard let v = version, !v.isEmpty else { return "—" }
        return "v\(v)"
    }

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
