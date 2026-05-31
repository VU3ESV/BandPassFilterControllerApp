import Foundation

/// Mirrors the EEPROM v2 config the firmware persists and exposes through the
/// `/` web form and `POST /save`.
struct DeviceConfig: Equatable {
    var wifiSSID: String = ""
    var wifiPassword: String = ""
    var hostname: String = "SO2R-BPF"

    var radio1Host: String = ""
    var radio1Port: Int = 50001
    var radio1IARU: Int = 0

    var radio2Host: String = ""
    var radio2Port: Int = 50001
    var radio2IARU: Int = 0

    /// URL-encoded form body matching the firmware's `/save` handler field names
    /// (WebPortal.h handleSave: ssid/pass/hostname, r{1,2}_host/_port/_iaru).
    /// IARU is only applied by the firmware when 1...3; 0 means "leave unchanged".
    func formBody() -> String {
        var items = URLComponents()
        var fields = [
            URLQueryItem(name: "ssid", value: wifiSSID),
            URLQueryItem(name: "pass", value: wifiPassword),
            URLQueryItem(name: "hostname", value: hostname),
            URLQueryItem(name: "r1_host", value: radio1Host),
            URLQueryItem(name: "r1_port", value: String(radio1Port)),
            URLQueryItem(name: "r2_host", value: radio2Host),
            URLQueryItem(name: "r2_port", value: String(radio2Port))
        ]
        if (1...3).contains(radio1IARU) {
            fields.append(URLQueryItem(name: "r1_iaru", value: String(radio1IARU)))
        }
        if (1...3).contains(radio2IARU) {
            fields.append(URLQueryItem(name: "r2_iaru", value: String(radio2IARU)))
        }
        items.queryItems = fields
        return items.percentEncodedQuery ?? ""
    }
}
