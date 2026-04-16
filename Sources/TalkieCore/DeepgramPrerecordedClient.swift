import Foundation

enum DeepgramPrerecordedClient {
    private static let endpoint = URL(string: "https://api.deepgram.com/v1/listen")!
    private static let timeoutInterval: TimeInterval = 60

    static func transcribe(fileURL: URL, apiKey: String, language: DeepgramLanguage) async throws -> String {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "smart_format", value: "true")
        ]

        if language == .automatic {
            queryItems.append(URLQueryItem(name: "detect_language", value: "true"))
        } else {
            queryItems.append(URLQueryItem(name: "language", value: language.deepgramCode))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url ?? endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepgramPrerecordedError.invalidResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw DeepgramPrerecordedError.httpError(
                    statusCode: httpResponse.statusCode,
                    body: preview(body)
                )
            }

            let decoded = try JSONDecoder().decode(DeepgramPrerecordedResponse.self, from: data)
            let transcript = decoded.results.channels.first?.alternatives.first?.transcript?.trimmed ?? ""
            if transcript.isEmpty {
                throw DeepgramPrerecordedError.noTranscript
            }
            return transcript
        } catch let error as URLError {
            throw DeepgramPrerecordedError.requestFailed(reason: error.localizedDescription)
        }
    }

    private static func preview(_ text: String, maxLength: Int = 400) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmed
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "…"
    }
}

enum DeepgramPrerecordedError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noTranscript
    case requestFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Deepgram."
        case .httpError(let statusCode, let body):
            return "Deepgram HTTP \(statusCode): \(body)"
        case .noTranscript:
            return "Deepgram returned no transcript."
        case .requestFailed(let reason):
            return "Deepgram request failed: \(reason)"
        }
    }
}

private struct DeepgramPrerecordedResponse: Decodable {
    struct Results: Decodable {
        struct Channel: Decodable {
            struct Alternative: Decodable {
                let transcript: String?
            }

            let alternatives: [Alternative]
        }

        let channels: [Channel]
    }

    let results: Results
}
