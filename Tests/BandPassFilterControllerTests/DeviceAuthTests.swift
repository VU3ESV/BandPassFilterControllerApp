import XCTest
@testable import BandPassFilterController

/// Device-auth pieces that don't need a device (or the Keychain).
final class DeviceAuthTests: XCTestCase {

    // MARK: - Challenge policy

    func testDigestChallengeIsAnsweredAsAdmin() {
        XCTAssertEqual(
            DeviceAuth.decide(method: NSURLAuthenticationMethodHTTPDigest, previousFailureCount: 0, password: "s3cret"),
            .answer(user: "admin", password: "s3cret"))
    }

    func testBasicChallengeIsRefusedWithoutSendingThePassword() {
        for password in ["s3cret", nil] as [String?] {
            XCTAssertEqual(
                DeviceAuth.decide(method: NSURLAuthenticationMethodHTTPBasic, previousFailureCount: 0, password: password),
                .cancel(.insecureAuthRefused))
        }
    }

    func testNoStoredPasswordCancelsAsRequired() {
        for password in [nil, ""] as [String?] {
            XCTAssertEqual(
                DeviceAuth.decide(method: NSURLAuthenticationMethodHTTPDigest, previousFailureCount: 0, password: password),
                .cancel(.passwordRequired))
        }
    }

    func testRepeatChallengeCancelsAsRejected() {
        XCTAssertEqual(
            DeviceAuth.decide(method: NSURLAuthenticationMethodHTTPDigest, previousFailureCount: 1, password: "wrong"),
            .cancel(.passwordRejected))
    }

    func testNonHTTPAuthChallengeUsesDefaultHandling() {
        XCTAssertEqual(
            DeviceAuth.decide(method: NSURLAuthenticationMethodServerTrust, previousFailureCount: 0, password: "s3cret"),
            .performDefault)
    }

    // MARK: - HTTP status mapping

    func testUnauthorizedWithoutPasswordIsPasswordRequired() {
        XCTAssertEqual(BPFClient.error(forStatus: 401, passwordSupplied: false), .passwordRequired)
    }

    func testUnauthorizedWithPasswordIsPasswordRejected() {
        XCTAssertEqual(BPFClient.error(forStatus: 401, passwordSupplied: true), .passwordRejected)
    }

    func testSuccessAndOtherStatuses() {
        XCTAssertNil(BPFClient.error(forStatus: 200, passwordSupplied: false))
        XCTAssertNil(BPFClient.error(forStatus: 204, passwordSupplied: true))
        XCTAssertEqual(BPFClient.error(forStatus: 400, passwordSupplied: true), .badResponse(400))
        XCTAssertEqual(BPFClient.error(forStatus: 503, passwordSupplied: false), .badResponse(503))
    }

    func testAuthErrorsAreDistinctAndDescribed() {
        XCTAssertTrue(BPFClientError.passwordRequired.isAuthFailure)
        XCTAssertTrue(BPFClientError.passwordRejected.isAuthFailure)
        XCTAssertFalse(BPFClientError.badResponse(401).isAuthFailure)
        XCTAssertFalse(BPFClientError.transport("offline").isAuthFailure)
        XCTAssertEqual(BPFClientError.passwordRequired.errorDescription?.hasPrefix("Device requires a password"), true)
        XCTAssertEqual(BPFClientError.passwordRejected.errorDescription?.hasPrefix("Device rejected the password"), true)
    }

    // MARK: - /discover auth_required

    private func identity(_ json: String) throws -> DeviceIdentity {
        try JSONDecoder().decode(DeviceIdentity.self, from: Data(json.utf8))
    }

    func testAuthRequiredTrue() throws {
        let id = try identity(#"{"service":"bpf-so2r","hostname":"BPF-SO2R","auth_required":true}"#)
        XCTAssertTrue(id.requiresAuth)
        XCTAssertEqual(id.hostname, "BPF-SO2R")
    }

    func testAuthRequiredFalse() throws {
        XCTAssertFalse(try identity(#"{"hostname":"BPF-SO2R","auth_required":false}"#).requiresAuth)
    }

    func testAuthRequiredMissingOnOlderFirmwareReadsFalse() throws {
        let id = try identity(#"{"service":"bpf-so2r","version":"0.5.0","hostname":"SO2R-BPF","bpf_count":2}"#)
        XCTAssertNil(id.authRequired)
        XCTAssertFalse(id.requiresAuth)
    }
}
