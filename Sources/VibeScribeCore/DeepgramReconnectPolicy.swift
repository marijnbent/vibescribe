import Foundation

enum DeepgramReconnectPolicy {
    static let maxAttempts = 1

    static func shouldRetry(currentAttempt: Int) -> Bool {
        currentAttempt < maxAttempts
    }
}
