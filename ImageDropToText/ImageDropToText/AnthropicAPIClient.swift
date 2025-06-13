import Foundation

// MARK: - Public Data Structures for Conversation

/// Represents a single turn in a conversation for the Anthropic API.
public struct AnthropicConversationTurn: Codable, Hashable {
    public let role: AnthropicRole
    public let content: String
    
    public init(role: AnthropicRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// The role of the author of a conversation turn.
public enum AnthropicRole: String, Codable, Hashable {
    case user
    case assistant
}

/// Information about an available Anthropic model.
public struct AnthropicModel: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let description: String
}


// MARK: - Anthropic API Client
public final class AnthropicAPIClient {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let session: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    
    private static let apiBaseURL = "https://api.anthropic.com/v1"
    private static let anthropicVersion = "2023-06-01"

    // MARK: - Custom Errors
    
    public enum AnthropicError: Error, LocalizedError {
        case apiKeyMissing
        case invalidURL
        case requestFailed(statusCode: Int, message: String)
        case decodingError(Error)
        case noContentAvailable
        case requestTimedOut
        
        public var errorDescription: String? {
            switch self {
            case .apiKeyMissing:
                return "Anthropic API key is missing."
            case .invalidURL:
                return "The endpoint URL is invalid."
            case .requestFailed(let code, let msg):
                return "API request failed with status code \(code): \(msg)"
            case .decodingError(let err):
                return "Failed to decode the response: \(err.localizedDescription)"
            case .noContentAvailable:
                return "The API response did not contain any valid text content."
            case .requestTimedOut:
                return "The network request timed out after 30 seconds."
            }
        }
    }
    
    // MARK: - Initializer
    
    public init(apiKey: String) {
        self.apiKey = apiKey
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45.0
        self.session = URLSession(configuration: configuration)
        
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    
    // MARK: - Public Methods
    
    /// This static method returns a hardcoded list of popular models.
    /// For the most up-to-date list, see: https://docs.anthropic.com/claude/docs/models-overview
    public static func getAvailableModels() -> [AnthropicModel] {
        return [
            .init(name: "claude-opus-4-0", description: "Our most capable model."),
            .init(name: "claude-sonnet-4-0", description: "High-performance model.")
        ]
    }
    
    /// Creates a message to continue a conversation.
    /// - Parameters:
    ///   - modelId: The ID of the model to use (e.g., "claude-3-sonnet-20240229").
    ///   - history: The conversation history, an array of `AnthropicConversationTurn`.
    ///   - systemPrompt: An optional high-level instruction for the model.
    ///   - maxTokens: The maximum number of tokens to generate.
    /// - Returns: The response text from the assistant.
    public func createMessage(
        modelId: String,
        history: [AnthropicConversationTurn],
        systemPrompt: String? = nil,
        maxTokens: Int = 4096
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw AnthropicError.apiKeyMissing }
        guard !history.isEmpty else { throw AnthropicError.noContentAvailable }
        
        let urlString = "\(Self.apiBaseURL)/messages"
        guard let url = URL(string: urlString) else { throw AnthropicError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        
        let requestBody = MessageRequest(
            model: modelId,
            maxTokens: maxTokens,
            system: systemPrompt,
            messages: history.map { Message(role: $0.role.rawValue, content: $0.content) }
        )
        
        do {
            request.httpBody = try jsonEncoder.encode(requestBody)
        } catch {
            throw AnthropicError.decodingError(error) // Encoding error
        }
        
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw AnthropicError.requestTimedOut
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.requestFailed(statusCode: -1, message: "Invalid response from server.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode the specific Anthropic error format
            if let errorResponse = try? jsonDecoder.decode(AnthropicErrorResponse.self, from: data) {
                throw AnthropicError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.error.message
                )
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AnthropicError.requestFailed(
                    statusCode: httpResponse.statusCode,
                    message: errorMessage
                )
            }
        }
        
        do {
            let apiResponse = try jsonDecoder.decode(MessageResponse.self, from: data)
            // Extract the first piece of text content from the response blocks
            guard let responseText = apiResponse.content.first(where: { $0.type == "text" })?.text else {
                throw AnthropicError.noContentAvailable
            }
            return responseText
        } catch {
            throw AnthropicError.decodingError(error)
        }
    }
}


// MARK: - Private Codable Data Models
private extension AnthropicAPIClient {
    
    // MARK: Request Structures
    struct MessageRequest: Codable {
        let model: String
        let maxTokens: Int
        let system: String?
        let messages: [Message]
    }

    struct Message: Codable {
        let role: String
        let content: String
    }
    
    // MARK: Success Response Structures
    struct MessageResponse: Codable {
        let id: String
        let type: String
        let role: String
        let content: [ContentBlock]
        let model: String
        let stopReason: String
        let usage: Usage
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String
    }
    
    struct Usage: Codable {
        let inputTokens: Int
        let outputTokens: Int
    }

    // MARK: Error Response Structure
    struct AnthropicErrorResponse: Codable {
        let type: String
        let error: APIErrorDetail
    }

    struct APIErrorDetail: Codable {
        let type: String
        let message: String
    }
}

//Example Usage (SwiftUI)
//This example shows how to build a chat interface that uses a Picker to select the model and manages the conversation history.
//Remember to add your Anthropic API Key to your Secrets.plist file with the key name ANTHROPIC_API_KEY. You can adapt the APIKeyManager from the previous example.
//import SwiftUI
//
//struct AnthropicChatView: View {
//    // State for the UI
//    @State private var currentPrompt: String = ""
//    @State private var conversationHistory: [AnthropicConversationTurn] = []
//    @State private var isLoading: Bool = false
//    @State private var errorMessage: String?
//    
//    // Model selection
//    private let availableModels = AnthropicAPIClient.getAvailableModels()
//    @State private var selectedModel: AnthropicModel
//
//    // Initialize the API client
//    private let anthropicClient: AnthropicAPIClient
//    
//    init() {
//        // Initialize state properties
//        _selectedModel = State(initialValue: AnthropicAPIClient.getAvailableModels().first!)
//        
//        // Load API key securely (adapt APIKeyManager as needed)
//        let apiKey = APIKeyManager.getAnthropicAPIKey() // Assumes a new method in your manager
//        self.anthropicClient = AnthropicAPIClient(apiKey: apiKey)
//    }
//
//    var body: some View {
//        VStack(spacing: 0) {
//            // Model Picker
//            Picker("Select Model", selection: $selectedModel) {
//                ForEach(availableModels) { model in
//                    Text(model.name).tag(model)
//                }
//            }
//            .pickerStyle(.segmented)
//            .padding()
//
//            // Conversation History
//            ScrollViewReader { proxy in
//                ScrollView {
//                    VStack(alignment: .leading, spacing: 12) {
//                        ForEach(conversationHistory, id: \.self) { turn in
//                            MessageBubble(turn: turn)
//                        }
//                        if isLoading {
//                            HStack { ProgressView(); Text("Claude is thinking...") }
//                        }
//                    }.padding()
//                    .id("bottom")
//                }
//                .onChange(of: conversationHistory) { _ in
//                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
//                }
//            }
//
//            if let errorMessage {
//                Text(errorMessage).foregroundColor(.red).padding()
//            }
//            
//            // Input Area
//            HStack {
//                TextField("Ask Claude...", text: $currentPrompt)
//                    .textFieldStyle(RoundedBorderTextFieldStyle())
//                Button(action: sendMessage) {
//                    Image(systemName: "arrow.up.circle.fill").font(.title)
//                }
//                .disabled(currentPrompt.isEmpty || isLoading)
//            }.padding()
//        }
//        .navigationTitle("Anthropic Chat")
//    }
//    
//    @MainActor
//    private func sendMessage() {
//        isLoading = true
//        errorMessage = nil
//        let userTurn = AnthropicConversationTurn(role: .user, content: currentPrompt)
//        conversationHistory.append(userTurn)
//        
//        // Clear the text field
//        currentPrompt = ""
//
//        Task {
//            do {
//                let result = try await anthropicClient.createMessage(
//                    modelId: selectedModel.id,
//                    history: conversationHistory,
//                    systemPrompt: "You are a helpful and concise assistant."
//                )
//                let assistantTurn = AnthropicConversationTurn(role: .assistant, content: result)
//                conversationHistory.append(assistantTurn)
//            } catch {
//                errorMessage = error.localizedDescription
//                _ = conversationHistory.popLast() // Remove the user's message on failure
//            }
//            isLoading = false
//        }
//    }
//}
//
//// Simple view for a message bubble
//struct MessageBubble: View {
//    let turn: AnthropicConversationTurn
//    var body: some View {
//        Text(turn.content)
//            .padding(12)
//            .background(turn.role == .user ? Color.blue.opacity(0.8) : Color(UIColor.systemGray4))
//            .foregroundColor(turn.role == .user ? .white : .primary)
//            .cornerRadius(12)
//            .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
//    }
//}
