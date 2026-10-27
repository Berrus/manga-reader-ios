import XCTest
import UIKit
@testable import MangaReader

/// Unit tests run inside the app, so Bundle.main is the built app: this checks that the
/// alternate icons really made it into the built Info.plist.
final class AppIconTests: XCTestCase {
    func testBuiltInfoPlistDeclaresEveryAlternateIcon() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
                                  "CFBundleIcons is missing from the built Info.plist")
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any],
                                       "No CFBundleAlternateIcons: the asset catalog's alternate icons were not registered")
        for choice in AppIconChoice.allCases {
            guard let name = choice.iconName else { continue }
            XCTAssertNotNil(alternates[name], "\(name) is not declared as an alternate icon")
        }
    }

    func testEveryIconChoiceHasAPreviewImage() {
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.preview), "Missing preview image \(choice.preview)")
        }
    }

    func testOnlyTheTemporarilyUnavailableErrorIsRetried() {
        XCTAssertTrue(AppIconPicker.isTransient(NSError(domain: NSPOSIXErrorDomain, code: 35)))
        XCTAssertFalse(AppIconPicker.isTransient(NSError(domain: NSPOSIXErrorDomain, code: 2)))
        XCTAssertFalse(AppIconPicker.isTransient(NSError(domain: NSCocoaErrorDomain, code: 35)))
    }
}
