import XCTest
@testable import UserbackSDK

final class UserbackSDKTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(UserbackSDK.version(), "0.1.0")
    }
}
