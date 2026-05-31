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

/// Decodes the firmware's `GET /config` JSON (WebPortal.h handleConfig):
///   { "ssid", "hostname", "r1": {host,port,iaru}, "r2": {host,port,iaru} }
/// The Wi-Fi password is not returned by the device, so it stays empty here —
/// matching the "leave blank to keep current" behaviour of `/save`.
/// Declared in an extension so the memberwise/default initializers survive.
extension DeviceConfig: Decodable {
    private enum CodingKeys: String, CodingKey {
        case ssid, hostname, r1, r2
    }
    private enum RadioKeys: String, CodingKey {
        case host, port, iaru
    }

    init(from decoder: Decoder) throws {
        self.init()  // start from defaults, then overlay whatever the device sent
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wifiSSID = (try? c.decode(String.self, forKey: .ssid)) ?? wifiSSID
        hostname = (try? c.decode(String.self, forKey: .hostname)) ?? hostname

        if let r1 = try? c.nestedContainer(keyedBy: RadioKeys.self, forKey: .r1) {
            radio1Host = (try? r1.decode(String.self, forKey: .host)) ?? radio1Host
            radio1Port = (try? r1.decode(Int.self, forKey: .port)) ?? radio1Port
            radio1IARU = (try? r1.decode(Int.self, forKey: .iaru)) ?? radio1IARU
        }
        if let r2 = try? c.nestedContainer(keyedBy: RadioKeys.self, forKey: .r2) {
            radio2Host = (try? r2.decode(String.self, forKey: .host)) ?? radio2Host
            radio2Port = (try? r2.decode(Int.self, forKey: .port)) ?? radio2Port
            radio2IARU = (try? r2.decode(Int.self, forKey: .iaru)) ?? radio2IARU
        }
    }
}
