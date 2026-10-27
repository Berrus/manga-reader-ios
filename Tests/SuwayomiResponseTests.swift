import XCTest
@testable import MangaReader

final class SuwayomiResponseTests: XCTestCase {
    func testInstalledSourcesAndServerDecode() throws {
        let json = #"{"data":{"aboutServer":{"name":"Suwayomi","version":"2.3"},"sources":{"nodes":[{"id":"123","displayName":"Example","lang":"en"}]}}}"#
        let response = try JSONDecoder().decode(SuwayomiResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.data?.aboutServer?.name, "Suwayomi")
        XCTAssertEqual(response.data?.sources?.nodes.first?.id, "123")
        XCTAssertNil(response.errors)
    }

    func testGraphQLErrorsAreDecoded() throws {
        let json = #"{"data":null,"errors":[{"message":"Unauthorized"}]}"#
        let response = try JSONDecoder().decode(SuwayomiResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.errors?.first?.message, "Unauthorized")
        XCTAssertNil(response.data)
    }
}
