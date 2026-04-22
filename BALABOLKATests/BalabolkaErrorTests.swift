import XCTest
@testable import BALABOLKA

final class BalabolkaErrorTests: XCTestCase {
    func testDailyQuotaExceededMessageIsUserFacing() {
        let message = BalabolkaError.badStatus(
            429,
            #"{"error":"UPSTREAM_QUOTA_EXCEEDED","quotaScope":"daily","message":"Quota exceeded for metric: generativelanguage.googleapis.com/generate_requests_per_model_per_day"}"#
        ).errorDescription

        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("Квота Gemini TTS на сегодня исчерпана") == true)
    }
}
