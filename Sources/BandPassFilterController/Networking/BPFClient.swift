import Foundation

enum BPFClientError: LocalizedError, Equatable {
    case invalidHost
    case badResponse(Int)
    case transport(String)
    case decoding(String)
    /// HTTP 401 and no password is stored for this device (firmware ≥ v0.6.0).
    case passwordRequired
    /// HTTP 401 although a password was sent — it's wrong.
    case passwordRejected

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
        case .passwordRequired:
            return "Device requires a password. Enter it under Settings ▸ Device Password."
        case .passwordRejected:
            return "Device rejected the password. Check it under Settings ▸ Device Password."
        }
    }

    var isAuthFailure: Bool { self == .passwordRequired || self == .passwordRejected }
}

/// Thin async client over the firmware's HTTP API.
///
/// Routes (from the firmware web server):
///   GET  /discover                     -> JSON DeviceIdentity (vendor/product/version)
///   GET  /status                       -> JSON DeviceStatus (version, sensors, history)
///   GET  /config                       -> JSON DeviceConfig (stored settings / backup)
///   POST /save           (form body)   -> "Saved"
///   POST /bypass?bpf=&on=              -> manual bypass
///   POST /history?clear=YES            -> clear band-change history
///   POST /reboot                       -> soft reboot
///   POST /factory_reset?confirm=YES    -> EEPROM zeroed + reboot
///   GET  /live                         -> live HTML page (opened in a browser)
///
/// Firmware ≥ v0.6.0 with an admin password set answers `GET /` and every POST
/// with a Digest challenge; `DeviceAuthDelegate` answers it with `password`.
struct BPFClient {
    /// Base host as the user typed it, e.g. "SO2R-BPF.local" or "192.168.4.1".
    let host: String
    let timeout: TimeInterval
    /// Device admin password (user `admin`) from the Keychain; nil if none stored.
    let password: String?

    init(host: String, password: String? = nil, timeout: TimeInterval = 4.0) {
        self.host = host
        self.password = password
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

    // MARK: - Discovery

    /// Identify a device by its static `/discover` record. Used to confirm a
    /// typed/discovered address really is a BPF controller and show its identity.
    func fetchDiscover() async throws -> DeviceIdentity {
        try await getJSON("discover")
    }

    // MARK: - Status

    func fetchStatus() async throws -> DeviceStatus {
        try await getJSON("status")
    }

    // MARK: - Config

    /// Read the device's stored configuration (host/port/IARU/SSID/hostname).
    /// The firmware never returns the Wi-Fi password, so it decodes as empty.
    func fetchConfig() async throws -> DeviceConfig {
        try await getJSON("config")
    }

    /// Raw `/config` JSON bytes, used for the "Download config" backup so the
    /// saved file is byte-for-byte what the firmware serves.
    func fetchConfigData() async throws -> Data {
        try await send(jsonRequest("config"))
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
        try await postTolerantOfRestart(url: url)
    }

    func factoryReset() async throws {
        var components = URLComponents(url: try baseURL().appendingPathComponent("factory_reset"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "confirm", value: "YES")]
        guard let url = components?.url else { throw BPFClientError.invalidHost }
        try await postTolerantOfRestart(url: url)
    }

    // MARK: - Helpers

    /// The device restarts and may drop the connection before replying, so
    /// transport errors are tolerated — but a refused password is not.
    private func postTolerantOfRestart(url: URL) async throws {
        do {
            try await postForm(url: url, body: "")
        } catch let error as BPFClientError where error.isAuthFailure {
            throw error
        } catch {
            return
        }
    }

    private func jsonRequest(_ path: String) throws -> URLRequest {
        var request = URLRequest(url: try baseURL().appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(jsonRequest(path))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BPFClientError.decoding(error.localizedDescription)
        }
    }

    private func postForm(url: URL, body: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        _ = try await send(request)
    }

    /// Run one request on its own ephemeral session whose delegate answers the
    /// device's auth challenge. The session is invalidated afterwards, which
    /// also releases the delegate (sessions hold theirs strongly).
    private func send(_ request: URLRequest) async throws -> Data {
        let auth = DeviceAuthDelegate(password: password)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: auth, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // A challenge we cancelled surfaces as a cancelled task; say why.
            if let failure = auth.failure { throw failure }
            throw BPFClientError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { return data }
        if http.statusCode == 401, let failure = auth.failure { throw failure }
        if let error = Self.error(forStatus: http.statusCode, passwordSupplied: password?.isEmpty == false) {
            throw error
        }
        return data
    }

    /// Map an HTTP status to an error (nil for 2xx). A 401 becomes a typed auth
    /// error, split on whether we had a password to offer.
    static func error(forStatus code: Int, passwordSupplied: Bool) -> BPFClientError? {
        if (200..<300).contains(code) { return nil }
        if code == 401 { return passwordSupplied ? .passwordRejected : .passwordRequired }
        return .badResponse(code)
    }
}
