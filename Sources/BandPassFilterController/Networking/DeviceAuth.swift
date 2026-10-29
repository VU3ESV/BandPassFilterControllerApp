import Foundation

/// HTTP auth for firmware ≥ v0.6.0. When the device has an admin password set,
/// `GET /` and every mutating `POST` answer 401 with
/// `WWW-Authenticate: Digest realm="BandPassFilterController", ...`
/// (ESP32 `WebServer::requestAuthentication(DIGEST_AUTH, realm)`). The username
/// is always `admin`; the password lives in the Keychain (see `DeviceKeychain`).
enum DeviceAuth {
    static let username = "admin"
    static let realm = "BandPassFilterController"

    /// What to do with one URLSession auth challenge.
    enum Decision: Equatable {
        case answer(user: String, password: String)
        /// Give up; the request fails with this typed error.
        case cancel(BPFClientError)
        /// Not an HTTP auth challenge (e.g. TLS server trust) — let the system handle it.
        case performDefault
    }

    /// Pure challenge policy, factored out of the delegate so it is unit-testable.
    ///
    /// The ESP32 keeps a single server nonce and regenerates it on every new
    /// challenge, so a fresh 401 is normal and is answered again; only a repeat
    /// within the same request (`previousFailureCount > 0`) means the password
    /// was actually rejected.
    static func decide(method: String, previousFailureCount: Int, password: String?) -> Decision {
        guard method == NSURLAuthenticationMethodHTTPDigest
                || method == NSURLAuthenticationMethodHTTPBasic else {
            return .performDefault
        }
        guard let password, !password.isEmpty else { return .cancel(.passwordRequired) }
        guard previousFailureCount == 0 else { return .cancel(.passwordRejected) }
        return .answer(user: username, password: password)
    }
}

/// Per-request URLSession delegate that answers Digest/Basic challenges with the
/// stored device password, and remembers why it cancelled one so `BPFClient`
/// can throw `passwordRequired` / `passwordRejected` instead of a generic
/// "cancelled" transport error.
final class DeviceAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let password: String?
    private let lock = NSLock()
    private var cancelledWith: BPFClientError?

    init(password: String?) {
        self.password = password
    }

    /// The auth error behind a cancelled challenge, if any.
    var failure: BPFClientError? {
        lock.lock(); defer { lock.unlock() }
        return cancelledWith
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch DeviceAuth.decide(method: challenge.protectionSpace.authenticationMethod,
                                 previousFailureCount: challenge.previousFailureCount,
                                 password: password) {
        case .answer(let user, let password):
            completionHandler(.useCredential,
                              URLCredential(user: user, password: password, persistence: .forSession))
        case .cancel(let error):
            lock.lock(); cancelledWith = error; lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
        case .performDefault:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
