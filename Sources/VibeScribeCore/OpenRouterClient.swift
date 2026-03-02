import Foundation

enum OpenRouterClient {
    static func enhance(transcript: String, prompt: String, apiKey: String, model: String) async throws -> String {
        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenRouterError.httpError(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenRouterError.noContent
        }
        return content
    }
}

enum OpenRouterError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .httpError(let statusCode, let body):
            return "OpenRouter HTTP \(statusCode): \(body)"
        case .noContent:
            return "OpenRouter returned no content."
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
