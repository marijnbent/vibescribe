import XCTest
@testable import TalkieCore

final class RunningAppPickerModelTests: XCTestCase {
    func testNormalizedOptionsDeduplicateByBundleIdentifier() {
        let options = RunningAppPickerDataSource.normalizedOptions(
            from: [
                RunningApplicationSnapshotEntry(
                    bundleIdentifier: "com.apple.TextEdit",
                    displayName: "TextEdit",
                    bundleURL: nil
                ),
                RunningApplicationSnapshotEntry(
                    bundleIdentifier: "COM.APPLE.TEXTEDIT",
                    displayName: "TextEdit Duplicate",
                    bundleURL: nil
                )
            ],
            excludingBundleIdentifier: nil
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].bundleIdentifier, "com.apple.textedit")
        XCTAssertEqual(options[0].displayName, "TextEdit")
    }

    func testNormalizedOptionsFilterInvalidBundleIdentifiers() {
        let options = RunningAppPickerDataSource.normalizedOptions(
            from: [
                RunningApplicationSnapshotEntry(bundleIdentifier: nil, displayName: "Missing", bundleURL: nil),
                RunningApplicationSnapshotEntry(bundleIdentifier: "   ", displayName: "Blank", bundleURL: nil),
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.apple.Preview", displayName: "Preview", bundleURL: nil)
            ],
            excludingBundleIdentifier: nil
        )

        XCTAssertEqual(options.map(\.bundleIdentifier), ["com.apple.preview"])
    }

    func testNormalizedOptionsExcludeCurrentAppBundleIdentifier() {
        let options = RunningAppPickerDataSource.normalizedOptions(
            from: [
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.example.Talkie", displayName: "Talkie", bundleURL: nil),
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.apple.TextEdit", displayName: "TextEdit", bundleURL: nil)
            ],
            excludingBundleIdentifier: "com.example.talkie"
        )

        XCTAssertEqual(options.count, 1)
        XCTAssertEqual(options[0].bundleIdentifier, "com.apple.textedit")
    }

    func testNormalizedOptionsSortByDisplayNameThenBundleIdentifier() {
        let options = RunningAppPickerDataSource.normalizedOptions(
            from: [
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.apple.zeta", displayName: "Beta", bundleURL: nil),
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.apple.alpha", displayName: "Alpha", bundleURL: nil),
                RunningApplicationSnapshotEntry(bundleIdentifier: "com.apple.beta", displayName: "Beta", bundleURL: nil)
            ],
            excludingBundleIdentifier: nil
        )

        XCTAssertEqual(options.map(\.displayName), ["Alpha", "Beta", "Beta"])
        XCTAssertEqual(options.map(\.bundleIdentifier), ["com.apple.alpha", "com.apple.beta", "com.apple.zeta"])
    }
}
