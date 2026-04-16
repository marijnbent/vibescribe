import Foundation

enum OpenRouterClient {
    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private static let timeoutInterval: TimeInterval = 30

    static func enhance(transcript: String, prompt: String, apiKey: String, model: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let content = "\(prompt)\n\n<transcription>\(transcript)</transcription>"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, body: Self.preview(body))
            }

            let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw OpenRouterError.noContent
            }
            return content
        } catch let error as URLError {
            throw OpenRouterError.requestFailed(reason: error.localizedDescription)
        }
    }

    private static func preview(_ text: String, maxLength: Int = 400) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmed
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "…"
    }
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noContent
    case requestFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .httpError(let statusCode, let body):
            return "OpenRouter HTTP \(statusCode): \(body)"
        case .noContent:
            return "OpenRouter returned no content."
        case .requestFailed(let reason):
            return "OpenRouter request failed: \(reason)"
        }
    }
}

private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
