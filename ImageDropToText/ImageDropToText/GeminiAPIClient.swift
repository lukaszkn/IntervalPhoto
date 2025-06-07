import Foundation

// MARK: - Public Data Structures for Conversation

/// Represents a single turn in a conversation.
public struct ConversationTurn: Codable, Hashable {
    public let role: Role
    public let text: String
    
    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// The role of the author of a conversation turn.
public enum Role: String, Codable, Hashable {
    case user
    case model
}

// MARK: - Gemini API Client
public final class GeminiAPIClient {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let modelName: String
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    
    // MARK: - Custom Errors (Unchanged)
    
    public enum GeminiError: Error, LocalizedError {
        case apiKeyMissing, invalidURL, requestFailed(statusCode: Int, message: String), decodingError(Error), noContentAvailable, requestTimedOut
        
        public var errorDescription: String? {
            switch self {
            case .apiKeyMissing: "Gemini API key is missing..."
            case .invalidURL: "The endpoint URL is invalid."
            case .requestFailed(let code, let msg): "API request failed with status code \(code): \(msg)"
            case .decodingError(let err): "Failed to decode the response: \(err.localizedDescription)"
            case .noContentAvailable: "The API response did not contain any content."
            case .requestTimedOut: "The network request timed out after 30 seconds."
            }
        }
    }
    
    // MARK: - Initializer
    
    public init(apiKey: String, modelName: String = "gemini-2.5-pro-preview-06-05") {
        self.apiKey = apiKey
        self.modelName = modelName
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45.0
        self.session = URLSession(configuration: configuration)
        
        // Configure the JSON encoder to convert camelCase to snake_case
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
    }
    
    // MARK: - Public Methods
    
    /// Generates content for a single-turn prompt. A convenience wrapper for multi-turn conversation.
    /// - Parameters:
    ///   - prompt: The text prompt to send to the model.
    ///   - systemInstruction: Optional high-level instructions for the model.
    /// - Returns: The generated text content from the model.
    public func generateContent(prompt: String, systemInstruction: String? = nil) async throws -> String {
        // Wrap the single prompt in a conversation history array
        let history = [ConversationTurn(role: .user, text: prompt)]
        return try await generateContent(history: history, systemInstruction: systemInstruction)
    }

    /// Generates content based on a multi-turn conversation history.
    /// - Parameters:
    ///   - history: An array of `ConversationTurn` structs representing the conversation so far.
    ///   - systemInstruction: Optional high-level instructions for the model.
    /// - Returns: The generated text content from the model.
    public func generateContent(history: [ConversationTurn], systemInstruction: String? = nil) async throws -> String {
        guard !apiKey.isEmpty else { throw GeminiError.apiKeyMissing }
        
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw GeminiError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Create the request body from the history and optional system instruction
        let requestBody = RequestBody(
            contents: history.map { RequestContent(role: $0.role.rawValue, parts: [RequestPart(text: $0.text)]) },
            systemInstruction: systemInstruction != nil ? SystemInstruction(parts: [RequestPart(text: systemInstruction!)]) : nil
        )
        
        do {
            request.httpBody = try jsonEncoder.encode(requestBody)
        } catch {
            throw GeminiError.decodingError(error)
        }
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw GeminiError.requestTimedOut
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.requestFailed(statusCode: -1, message: "Invalid response from server.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "No error message"
            throw GeminiError.requestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        do {
            let apiResponse = try JSONDecoder().decode(APIResponse.self, from: data)
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
        let systemInstruction: SystemInstruction? // Optional
    }

    struct SystemInstruction: Codable {
        let parts: [RequestPart]
    }

    struct RequestContent: Codable {
        let role: String // "user" or "model"
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

//// This new example demonstrates how to manage a conversation history and use the system instruction.
//import SwiftUI
//
//struct ConversationView: View {
//    @State private var systemInstruction: String = "You are a helpful and friendly chatbot."
//    @State private var currentPrompt: String = ""
//    @State private var conversationHistory: [ConversationTurn] = []
//    @State private var isLoading: Bool = false
//    @State private var errorMessage: String?
//
//    // Initialize the client with the key from our secure manager
//    private let geminiClient = GeminiAPIClient(apiKey: APIKeyManager.getAPIKey())
//    
//    var body: some View {
//        VStack(spacing: 0) {
//            // System Instruction Input
//            TextField("System Instruction (optional)", text: $systemInstruction)
//                .padding()
//                .background(Color(.systemGray6))
//                .cornerRadius(8)
//                .padding([.horizontal, .top])
//
//            // Conversation History
//            ScrollViewReader { proxy in
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 12) {
//                        ForEach(conversationHistory, id: \.self) { turn in
//                            MessageView(turn: turn)
//                        }
//                        if isLoading {
//                            HStack {
//                                ProgressView()
//                                Text("Generating...")
//                                    .foregroundColor(.secondary)
//                            }
//                            .padding()
//                        }
//                    }
//                    .padding()
//                    .id("bottom") // ID to scroll to
//                }
//                .onChange(of: conversationHistory) { _ in
//                    withAnimation {
//                        proxy.scrollTo("bottom", anchor: .bottom)
//                    }
//                }
//            }
//
//            // Error Message
//            if let errorMessage {
//                Text(errorMessage)
//                    .foregroundColor(.red)
//                    .padding()
//            }
//            
//            // Input Area
//            HStack {
//                TextField("Ask something...", text: $currentPrompt)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                Button(action: sendMessage) {
//                    Image(systemName: "arrow.up.circle.fill")
//                        .font(.title)
//                }
//                .disabled(currentPrompt.isEmpty || isLoading)
//            }
//            .padding()
//        }
//        .navigationTitle("Gemini Chat")
//    }
//    
//    @MainActor
//    private func sendMessage() {
//        isLoading = true
//        errorMessage = nil
//        let userTurn = ConversationTurn(role: .user, text: currentPrompt)
//        conversationHistory.append(userTurn)
//        let promptToSend = currentPrompt
//        currentPrompt = ""
//
//        Task {
//            do {
//                // Use the new method with the full history
//                let result = try await geminiClient.generateContent(
//                    history: conversationHistory,
//                    systemInstruction: systemInstruction.isEmpty ? nil : systemInstruction
//                )
//                let modelTurn = ConversationTurn(role: .model, text: result)
//                conversationHistory.append(modelTurn)
//            } catch {
//                errorMessage = error.localizedDescription
//                // Optionally remove the user's last message if the call failed
//                _ = conversationHistory.popLast()
//            }
//            isLoading = false
//        }
//    }
//}
//
//// A simple view to display a single message bubble
//struct MessageView: View {
//    let turn: ConversationTurn
//    
//    var body: some View {
//        Text(turn.text)
//            .padding(10)
//            .background(turn.role == .user ? Color.blue.opacity(0.8) : Color.gray.opacity(0.4))
//            .foregroundColor(turn.role == .user ? .white : .primary)
//            .cornerRadius(10)
//            .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
//    }
//}
