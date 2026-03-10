import ApplicationServices
import Foundation

struct PasteVerificationExpectation: Equatable {
    let value: String
    let selectedRange: NSRange
}

enum PasteVerificationMatcher {
    static func expectedResult(
        initialValue: String,
        selectedRange: NSRange,
        insertedText: String
    ) -> PasteVerificationExpectation? {
        guard selectedRange.location != NSNotFound else { return nil }

        let valueNSString = initialValue as NSString
        let insertedNSString = insertedText as NSString
        guard NSMaxRange(selectedRange) <= valueNSString.length else { return nil }

        let expectedValue = valueNSString.replacingCharacters(in: selectedRange, with: insertedText)
        let expectedSelectedRange = NSRange(
            location: selectedRange.location + insertedNSString.length,
            length: 0
        )

        return PasteVerificationExpectation(
            value: expectedValue,
            selectedRange: expectedSelectedRange
        )
    }
}

final class AccessibilityPasteVerificationAdapter: PasteVerificationPort {
    private let systemWideElementProvider: () -> AXUIElement

    init(systemWideElementProvider: @escaping () -> AXUIElement = { AXUIElementCreateSystemWide() }) {
        self.systemWideElementProvider = systemWideElementProvider
    }

    func prepare(expectedText: String) -> PreparedPasteVerification? {
        guard AXIsProcessTrusted() else { return nil }
        guard let focusedElement = focusedElement() else { return nil }
        guard let initialValue = stringValue(of: focusedElement) else { return nil }
        guard let initialSelectedRange = selectedTextRange(of: focusedElement) else { return nil }
        guard let expectation = PasteVerificationMatcher.expectedResult(
            initialValue: initialValue,
            selectedRange: initialSelectedRange,
            insertedText: expectedText
        ) else {
            return nil
        }

        return PreparedPasteVerification(
            expectedText: expectedText,
            expectedValue: expectation.value,
            expectedSelectedRange: expectation.selectedRange,
            focusedElement: focusedElement,
            initialValue: initialValue,
            initialSelectedRange: initialSelectedRange
        )
    }

    func check(_ verification: PreparedPasteVerification) -> PasteVerificationCheck {
        guard AXIsProcessTrusted() else {
            return .unconfirmed(.accessibilityUnavailable)
        }
        guard let focusedElement = focusedElement() else {
            return .unconfirmed(.unsupportedFocusedElement)
        }
        guard CFEqual(focusedElement, verification.focusedElement) else {
            return .unconfirmed(.focusChanged)
        }
        guard let currentValue = stringValue(of: focusedElement) else {
            return .unconfirmed(.valueUnavailable)
        }
        guard let currentSelectedRange = selectedTextRange(of: focusedElement) else {
            return .unconfirmed(.selectionUnavailable)
        }

        if currentValue == verification.expectedValue &&
            NSEqualRanges(currentSelectedRange, verification.expectedSelectedRange) {
            return .confirmed
        }

        if currentValue == verification.initialValue &&
            NSEqualRanges(currentSelectedRange, verification.initialSelectedRange) {
            return .pending
        }

        return .unconfirmed(.mismatch)
    }

    private func focusedElement() -> AXUIElement? {
        let systemWideElement = systemWideElementProvider()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringValue(of element: AXUIElement) -> String? {
        guard let value = copyAttributeValue(kAXValueAttribute as CFString, from: element) else { return nil }
        return value as? String
    }

    private func selectedTextRange(of element: AXUIElement) -> NSRange? {
        guard let value = copyAttributeValue(kAXSelectedTextRangeAttribute as CFString, from: element) else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }

        var selectedRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &selectedRange) else { return nil }
        guard selectedRange.location >= 0, selectedRange.length >= 0 else { return nil }

        return NSRange(location: selectedRange.location, length: selectedRange.length)
    }

    private func copyAttributeValue(_ attribute: CFString, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value
    }
}
