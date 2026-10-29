import Foundation

/// Static identity record from the firmware's `GET /discover` endpoint
/// (added in firmware discovery batch). No live state — just who/what the
/// device is, so it's cheap to sweep across many controllers.
struct DeviceIdentity: Decodable, Equatable {
    var service: String?      // "bpf-so2r"
    var vendor: String?       // "VU3ESV"
    var product: String?      // "BandPassFilterController"
    var version: String?      // "0.5.0"
    var build: String?
    var hostname: String?     // configured mDNS hostname, e.g. "SO2R-BPF"
    var ip: String?
    var bpfCount: Int?
    /// Firmware ≥ v0.6.0: true when the device has an admin password set.
    /// Older firmware omits it (no auth there), so missing reads as false.
    var authRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case service, vendor, product, version, build, hostname, ip
        case bpfCount = "bpf_count"
        case authRequired = "auth_required"
    }

    var requiresAuth: Bool { authRequired ?? false }

    var productName: String { product ?? "BandPassFilterController" }
    var versionDisplay: String {
        guard let v = version, !v.isEmpty else { return "" }
        return "v\(v)"
    }
}
