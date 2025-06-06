import Foundation

// MARK: - Gemini API Client
final class GeminiAPIClient {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let modelName: String
    private let session: URLSession
    
    // MARK: - Custom Errors
    
    enum GeminiError: Error, LocalizedError {
        case apiKeyMissing
        case invalidURL
        case requestFailed(statusCode: Int, message: String)
        case decodingError(Error)
        case noContentAvailable
        
        var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "Gemini API key is missing. Please provide it during initialization."
            case .invalidURL:
                return "The endpoint URL is invalid."
            case .requestFailed(let statusCode, let message):
                return "API request failed with status code \(statusCode): \(message)"
            case .decodingError(let underlyingError):
                return "Failed to decode the response: \(underlyingError.localizedDescription)"
            case .noContentAvailable:
                return "The API response did not contain any content."
            }
        }
    }
    
    // MARK: - Initializer
    
    /// Initializes the Gemini API Client.
    /// - Parameters:
    ///   - apiKey: Your Gemini API key.
    ///   - modelName: The model to use, e.g., "gemini-1.5-flash-latest" or "gemini-2.0-flash".
    init(apiKey: String, modelName: String = "gemini-2.5-pro-preview-06-05") {
        self.apiKey = apiKey
        // Note: The user requested "gemini-2.0-flash". We can also use "gemini-1.5-flash-latest" which is a common, efficient choice.
        // Let's stick to the user request for the URL construction.
        self.modelName = modelName
        self.session = URLSession(configuration: .default)
    }
    
    // MARK: - Public Method
    
    /// Generates content based on a text prompt.
    /// - Parameter prompt: The text prompt to send to the model.
    /// - Returns: The generated text content from the model.
    /// - Throws: `GeminiError` if the request fails for any reason.
    func generateContent(prompt: String) async throws -> String {
        // 1. Validate API Key
        guard !apiKey.isEmpty else {
            throw GeminiError.apiKeyMissing
        }
        
        // 2. Construct URL
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiError.invalidURL
        }
        
        // 3. Prepare Request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 4. Create Request Body
        let requestBody = RequestBody(contents: [.init(parts: [.init(text: prompt)])])
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw GeminiError.decodingError(error) // Technically encoding, but fits the category
        }
        
        // 5. Perform Network Call
        let (data, response) = try await session.data(for: request)
        
        // 6. Handle Response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(statusCode: -1, message: "Invalid response from server.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode the error message from the API
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw GeminiError.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // 7. Decode Success Response and Extract Text
        do {
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            // Extract the first piece of text content from the response
            guard let responseText = apiResponse.candidates.first?.content.parts.first?.text else {
                throw GeminiError.noContentAvailable
            }
            return responseText
        } catch {
            throw GeminiError.decodingError(error)
        }
    }
}

// MARK: - Codable Data Models for API Request & Response

private extension GeminiAPIClient {
    
    // Request Structures
    struct RequestBody: Codable {
        let contents: [RequestContent]
    }

    struct RequestContent: Codable {
        let parts: [RequestPart]
    }

    struct RequestPart: Codable {
        let text: String
    }
    
    // Response Structures
    struct APIResponse: Codable {
        let candidates: [Candidate]
    }
    
    struct Candidate: Codable {
        let content: ResponseContent
    }
    
    struct ResponseContent: Codable {
        let parts: [ResponsePart]
        let role: String
    }
    
    struct ResponsePart: Codable {
        let text: String
    }
}
