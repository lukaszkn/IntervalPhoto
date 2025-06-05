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


import SwiftUI
import Vision
import ChatGPTSwift

struct ContentView: View {
    @State private var droppedImage: NSImage?
    @State private var text: String = "Image will be converted to text here..."
    @State private var textGPTOutput: String = "ChatGPT output goes here..."
    
    private var openApi: ChatGPTAPI!
    
    init() {
        let apiKey = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String ?? ""
        openApi = ChatGPTAPI(apiKey: apiKey)
    }
    
    var body: some View {
        VStack {
            if let image = droppedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150, height: 100)
                    .border(Color.gray)
            } else {
                Text("Drop an image file here")
                    .frame(width: 150, height: 100)
                    .border(Color.gray)
            }
            Spacer()
            TextEditor(text: $text)
            Spacer()
            Button("Prompt ChatGPT") {
                Task {
                    do {
                        let response = try await openApi.sendMessage(text: text)
                        
                        print(response)
                        DispatchQueue.main.async {
                            textGPTOutput = response
                        }
                    } catch {
                        print(error.localizedDescription)
                        DispatchQueue.main.async {
                            textGPTOutput = error.localizedDescription
                        }
                    }
                }
            }
            Spacer()
            TextEditor(text: $textGPTOutput)
        }
        .onDrop(of: [.fileURL, .png], isTargeted: nil) { providers in
            handleDrop(providers: providers)
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
}

#Preview {
    ContentView()
}
