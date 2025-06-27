//
//  ContentView.swift
//  ImageDropToText
//
//  Created by Lukasz on 23/04/2025.
//
// https://platform.openai.com/docs/models
// https://platform.openai.com/docs/pricing
// https://platform.openai.com/settings/organization/usage
// https://lmarena.ai/leaderboard
// https://platform.openai.com/docs/libraries/swift?language=python#swift


import SwiftUI
import Vision
import ChatGPTSwift
import ScreenCaptureKit
import AppKit

struct ContentView: View {
    @State private var droppedImage: NSImage?
    @State private var text: String = "Image will be converted to text here..."
    @State private var textGPTOutput: String = "LLM output goes here..."
    @State private var systemText: String = "You're data engineer"
    
    static private let modelsSelectorValues = [ChatGPTModel.gpt_hyphen_4_period_1.rawValue,
                                               ChatGPTModel.gpt_hyphen_4_period_1_hyphen_mini.rawValue,
                                               ChatGPTModel.gpt_hyphen_4_period_1_hyphen_nano.rawValue,
                                               ChatGPTModel.o3.rawValue,
                                               ChatGPTModel.o4_hyphen_mini.rawValue,
                                               "gemini-2.5-pro",
                                               "claude-opus-4-0",
                                               "claude-sonnet-4-0"
                                              ]
    @State private var modelSelection = modelsSelectorValues[1]
    @State private var isPerformingAction = false
    
    private var openApi: ChatGPTAPI!
    private var geminiClient: GeminiAPIClient!
    
    private let anthropicClient: AnthropicAPIClient!
    @State private var anthropicConversationHistory: [AnthropicConversationTurn] = []
    
    init() {
        openApi = ChatGPTAPI(apiKey: APIKeyManager.getOpenAIAPIKey())
        geminiClient = GeminiAPIClient(apiKey: APIKeyManager.getGeminiAPIKey())
        anthropicClient = AnthropicAPIClient(apiKey: APIKeyManager.getAnthropicAPIKey())
    }
    
    var body: some View {
        VStack {
            if let image = droppedImage {
                HStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150, height: 100)
                        .border(Color.gray)
                    
                    Button(action: {
                        promptGPT(includeImage: true)
                    }) {
                        Text("Prompt ChatGPT with image")
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true) // allows wrapping
                    }
                    .disabled(isPerformingAction)
                }
            } else {
                Text("Drop an image file here")
                    .frame(width: 150, height: 100)
                    .border(Color.gray)
            }
            Spacer()
            HStack {
                Button("Clear") {
                    text = ""
                }
                Spacer()
                Button("Clear prompt history") {
                    openApi.deleteHistoryList()
                    anthropicConversationHistory.removeAll()
                }
            }
            TextEditor(text: $text)
                .font(.caption.monospaced())
            Spacer()
            
            HStack {
                Text("System text:")
                Spacer()
                TextField("", text: $systemText)
            }
            
            HStack {
                Picker("Model", selection: $modelSelection) {
                    ForEach(ContentView.modelsSelectorValues, id: \.self) {
                        Text($0)
                    }
                }
                Button("Prompt ChatGPT") {
                    promptGPT(includeImage: false)
                }
                .disabled(isPerformingAction)
            }
            Spacer()
            TextEditor(text: $textGPTOutput)
        }
        .onDrop(of: [.fileURL, .png], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private func promptGPT(includeImage: Bool) {
        isPerformingAction = true
        Task {
            if modelSelection.contains("claude") {
                anthropicConversationHistory.append(AnthropicConversationTurn(role: .user, content: text))
                
                do {
                    let result = try await anthropicClient.createMessage(
                        modelId: modelSelection,
                        history: anthropicConversationHistory,
                        systemPrompt: systemText
                    )
                    let assistantTurn = AnthropicConversationTurn(role: .assistant, content: result)
                    anthropicConversationHistory.append(assistantTurn)
                    endPrompt(message: result)
                } catch {
                    endPrompt(message: error.localizedDescription)
                    _ = anthropicConversationHistory.popLast()
                }
            } else if modelSelection.contains("gemini") {
                do {
                    endPrompt(message: try await geminiClient.generateContent(prompt: text, systemInstruction: systemText))
                } catch {
                    // Handle errors from the API client
                    if let geminiError = error as? GeminiAPIClient.GeminiError {
                        endPrompt(message: "Error: \(geminiError.localizedDescription)")
                    } else {
                        endPrompt(message: "An unknown error occurred: \(error.localizedDescription)")
                    }
                }
            } else {
                do {
                    let response = try await openApi.sendMessage(text: text,
                                                                 model: ChatGPTModel(rawValue: modelSelection)!,
                                                                 systemText: systemText,
                                                                 imageData: includeImage ? droppedImage?.jpegData() : nil)
                    
                    endPrompt(message: response)
                } catch {
                    endPrompt(message: error.localizedDescription)
                }
            }
        }
    }
    
    private func endPrompt(message: String) {
        print(message)
        DispatchQueue.main.async {
            textGPTOutput = message
            isPerformingAction = false
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    DispatchQueue.main.async {
                        if let data = item as? Data,
                           let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL,
                           let nsImage = NSImage(contentsOf: url) {
                                droppedImage = nsImage
                                imageToText()
                        }
                    }
                }
                
                return true
            } else if provider.hasItemConformingToTypeIdentifier("public.png") {
                  // Direct image data (like screenshot from screen)
                  provider.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
                      if let data = data, let image = NSImage(data: data) {
                          DispatchQueue.main.async {
                              droppedImage = image
                              imageToText()
                          }
                      }
                  }
                
                  return true
              }
        }
        return false
    }
    
    private func imageToText() {
        guard let cgImage = droppedImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            output("Failed to convert NSImage to CGImage")
            return
        }
        
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                output("Text recognition error: \(error.localizedDescription)")
                return
            }

            let observations = request.results as? [VNRecognizedTextObservation] ?? []
            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            output(recognizedStrings.joined(separator: "\n"))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                output("Failed to perform text recognition: \(error.localizedDescription)")
            }
        }
    }
    
    private func output(_ textToOutput: String) {
        print(text)
        DispatchQueue.main.async {
            text = textToOutput
        }
    }
    
    func captureFullScreenImage(completion: @escaping (NSImage?) -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let error = error {
                print("Failed to get shareable content: \(error)")
                completion(nil)
                return
            }

            guard let display = content?.displays.first else {
                print("No display found")
                completion(nil)
                return
            }

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            let output = SingleFrameOutput { image in
                // Stop the stream once we have the frame
                Task {
                    try? await stream.stopCapture()
                }
                completion(image)
            }

            do {
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue.main)
            } catch {
                print("Failed to add stream output: \(error)")
                completion(nil)
                return
            }

            stream.startCapture { error in
                if let error = error {
                    print("Failed to start capture: \(error)")
                    completion(nil)
                }
            }
        }
    }
}

extension NSImage {
    func jpegData(compressionQuality: CGFloat = 0.8) -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

#Preview {
    ContentView()
}
