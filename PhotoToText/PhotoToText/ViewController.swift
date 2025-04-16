//
//  ViewController.swift
//  PhotoToText
//
//  Created by Lukasz on 15/04/2025.
//

import UIKit
import AVKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    @IBOutlet weak var label: UILabel!
    
    private var cameraOutput = AVCapturePhotoOutput()
    private var captureSession: AVCaptureSession?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCaptureSession()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession?.startRunning()
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: device) else {
            print("Couldn't create video input")
            return
        }
        
        session.addInput(input)
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        preview.frame = CGRect(origin: view.frame.origin, size: CGSize(width: view.frame.size.width / 2, height: view.frame.size.height / 2))
        preview.connection!.videoOrientation = .landscapeRight
        
        view.layer.addSublayer(preview)
        
        if session.canAddOutput(cameraOutput) {
            session.addOutput(cameraOutput)
            
            session.commitConfiguration()
            
            captureSession = session
        } else {
            print("Couldn't add camera output")
        }
    }
    
    private func takePhoto() {
        let settings = AVCapturePhotoSettings()
        
        self.cameraOutput.capturePhoto(with: settings, delegate: self as AVCapturePhotoCaptureDelegate)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("error occurred : \(error.localizedDescription)")
        }
        
        if let dataImage = photo.fileDataRepresentation() {
            let dataProvider = CGDataProvider(data: dataImage as CFData)
            let cgImage: CGImage! = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)

            // Save to camera roll
            UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImage), nil, nil, nil);
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            let request = VNRecognizeTextRequest { (request, error) in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
                print(observations)
                
                let recognizedStrings = observations.compactMap { observation in
                    return observation.topCandidates(1).first?.string
                }
                
                self.label.text = recognizedStrings.joined(separator: "\n")
                print(self.label.text)
                
                // copy to clipboard
                UIPasteboard.general.string = self.label.text
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            
            do {
                try requestHandler.perform([request])
            } catch {
                print("Unable to perform the requests: \(error).")
            }
      } else {
          print("AVCapturePhotoCaptureDelegate Error")
      }
    }

    @IBAction func takePhoto(_ sender: Any) {
        takePhoto()
    }
}

