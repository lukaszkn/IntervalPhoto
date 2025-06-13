//
//  APIKeyManager.swift
//  ImageDropToText
//
//  Created by Lukasz on 06/06/2025.
//

import Foundation

enum APIKeyManager {
    static func getGeminiAPIKey() -> String {
        return Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String ?? ""
    }
    
    static func getOpenAIAPIKey() -> String {
        return Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
    }
    
    static func getAnthropicAPIKey() -> String {
        return Bundle.main.infoDictionary?["ANTHROPIC_API_KEY"] as? String ?? ""
    }
}
