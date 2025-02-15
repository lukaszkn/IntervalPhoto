//
//  ViewController.swift
//  IntervalPhoto
//
//  Created by Lukasz on 15/02/2025.
//
//  mogrify -resize 640x640! *.JPG

import UIKit
import AVKit

class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {

    @IBOutlet weak var infoLabel: UILabel!
    
    private var cameraOutput = AVCapturePhotoOutput()
    private var captureSession: AVCaptureSession?
    private var photoIndex = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupCaptureSession()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession?.startRunning()
        }
        
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { timer in
            self.takePhoto()
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
            let cgImageRef: CGImage! = CGImage(jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)

            // Save to camera roll
            UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: cgImageRef), nil, nil, nil);
            
            infoLabel.text = "\(photoIndex)"
            photoIndex += 1
      } else {
          print("AVCapturePhotoCaptureDelegate Error")
      }
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: device) else {
            print("Couldn't create video input")
            return
        }
        
        session.addInput(input)
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.frame
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
}

