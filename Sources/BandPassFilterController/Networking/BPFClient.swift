import Foundation

enum BPFClientError: LocalizedError {
    case invalidHost
    case badResponse(Int)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "The device address is not a valid URL."
        case .badResponse(let code):
            return "Device returned HTTP \(code)."
        case .transport(let message):
            return message
        case .decoding(let message):
            return "Could not read device response: \(message)"
        }
    }
}

/// Thin async client over the firmware's HTTP API.
///
/// Routes (from the firmware web server):
///   GET  /status                       -> JSON DeviceStatus (version, sensors, history)
///   GET  /config                       -> JSON DeviceConfig (stored settings / backup)
///   POST /save           (form body)   -> "Saved"
///   POST /bypass?bpf=&on=              -> manual bypass
///   POST /history?clear=YES            -> clear band-change history
///   POST /reboot                       -> soft reboot
///   POST /factory_reset?confirm=YES    -> EEPROM zeroed + reboot
///   GET  /live                         -> live HTML page (opened in a browser)
struct BPFClient {
    /// Base host as the user typed it, e.g. "SO2R-BPF.local" or "192.168.4.1".
    let host: String
    let timeout: TimeInterval

    init(host: String, timeout: TimeInterval = 4.0) {
        self.host = host
        self.timeout = timeout
    }

    private func baseURL() throws -> URL {
        var raw = host.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { throw BPFClientError.invalidHost }
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "http://" + raw
        }
        guard let url = URL(string: raw) else { throw BPFClientError.invalidHost }
        return url
    }

    /// URL of a device web page (e.g. "" for the portal root, "live" for the
    /// live page) for opening in an external browser. nil if the host is invalid.
    func pageURL(_ path: String = "") -> URL? {
        guard let base = try? baseURL() else { return nil }
        return path.isEmpty ? base : base.appendingPathComponent(path)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    // MARK: - Status

    func fetchStatus() async throws -> DeviceStatus {
        let url = try baseURL().appendingPathComponent("status")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session().data(for: request)
        } catch {
            throw BPFClientError.transport(error.localizedDescription)
        }
        try Self.validate(response)
        do {
            return try JSONDecoder().decode(DeviceStatus.self, from: data)
        } catch {
            throw BPFClientError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Config

    /// Read the device's stored configuration (host/port/IARU/SSID/hostname).
    /// The firmware never returns the Wi-Fi password, so it decodes as empty.
    func fetchConfig() async throws -> DeviceConfig {
        let url = try baseURL().appendingPathComponent("config")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session().data(for: request)
        } catch {
            throw BPFClientError.transport(error.localizedDescription)
        }
        try Self.validate(response)
        do {
            return try JSONDecoder().decode(DeviceConfig.self, from: data)
        } catch {
            throw BPFClientError.decoding(error.localizedDescription)
        }
    }

    /// Raw `/config` JSON bytes, used for the "Download config" backup so the
    /// saved file is byte-for-byte what the firmware serves.
    func fetchConfigData() async throws -> Data {
        let url = try baseURL().appendingPathComponent("config")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session().data(for: request)
        } catch {
            throw BPFClientError.transport(error.localizedDescription)
        }
        try Self.validate(response)
        return data
    }

    // MARK: - Mutations

    func saveConfig(_ config: DeviceConfig) async throws {
        let url = try baseURL().appendingPathComponent("save")
        try await postForm(url: url, body: config.formBody())
    }

    /// Clear the firmware's band-change history ring buffer (POST /history?clear=YES).
    func clearHistory() async throws {
        var components = URLComponents(url: try baseURL().appendingPathComponent("history"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "clear", value: "YES")]
        guard let url = components?.url else { throw BPFClientError.invalidHost }
        try await postForm(url: url, body: "")
    }

    func setBypass(bpf: Int, on: Bool) async throws {
        var components = URLComponents(url: try baseURL().appendingPathComponent("bypass"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "bpf", value: String(bpf)),
            URLQueryItem(name: "on", value: on ? "1" : "0")
        ]
        guard let url = components?.url else { throw BPFClientError.invalidHost }
        try await postForm(url: url, body: "")
    }

    func reboot() async throws {
        let url = try baseURL().appendingPathComponent("reboot")
        // The device restarts and may drop the connection; tolerate transport errors.
        try? await postForm(url: url, body: "")
    }

    func factoryReset() async throws {
        var components = URLComponents(url: try baseURL().appendingPathComponent("factory_reset"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "confirm", value: "YES")]
        guard let url = components?.url else { throw BPFClientError.invalidHost }
        try? await postForm(url: url, body: "")
    }

    // MARK: - Helpers

    private func postForm(url: URL, body: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let response: URLResponse
        do {
            (_, response) = try await session().data(for: request)
        } catch {
            throw BPFClientError.transport(error.localizedDescription)
        }
        try Self.validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw BPFClientError.badResponse(http.statusCode)
        }
    }
}
