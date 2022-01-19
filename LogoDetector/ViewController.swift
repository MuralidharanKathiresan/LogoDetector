//
//  ViewController.swift
//  LogoDetector
//
//  Created by Muralidharan Kathiresan on 03/01/22.
//

import UIKit
import AVFoundation
import CoreML
import Vision

final class ViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private lazy var logoDescription: UIButton = {
        let button = UIButton()
        button.backgroundColor = .lightGray.withAlphaComponent(0.3)
        button.titleLabel?.font = .boldSystemFont(ofSize: 30)
        button.titleLabel?.text = "..."
        button.titleLabel?.textColor = .white
        button.titleEdgeInsets = .init(top: 8, left: 8, bottom: 8, right: 8)
        self.view.addSubview(button)
        button.widthAnchor.constraint(equalToConstant: 250).isActive = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bottomAnchor.constraint(equalTo: self.view.bottomAnchor,
                                              constant: -35).isActive = true
        button.centerXAnchor.constraint(equalTo: self.view.centerXAnchor).isActive = true
        return button
    }()
        
    private lazy var classificationRequest: VNCoreMLRequest = {
        do {
            let configuration = MLModelConfiguration()
            let model = try VNCoreMLModel(for: LogoDetector(configuration: configuration).model)
            let request = VNCoreMLRequest(model: model,
                                          completionHandler: { [weak self] request, error in
                self?.processClassifications(for: request, error: error)
            })
            request.imageCropAndScaleOption = .centerCrop
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error.localizedDescription)")
        }
    }()
    
    private let photoOutput = AVCapturePhotoOutput()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.openCamera()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let imageData = photo.fileDataRepresentation() else { return }
        guard let image = UIImage(data: imageData) else { return }
        updateClassifications(for: image)
    }
}

private extension ViewController {
    func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { (granted) in
                if granted {
                    print("the user has granted to access the camera")
                    DispatchQueue.main.async {
                        self.setupCaptureSession()
                    }
                } else {
                    print("the user has not granted to access the camera")
                    self.handleDismiss()
                }
            }
            
        case .denied:
            print("the user has denied previously to access the camera.")
            self.handleDismiss()
            
        case .restricted:
            print("the user can't give camera access due to some restriction.")
            self.handleDismiss()
            
        default:
            print("something has wrong due to we can't access the camera.")
            self.handleDismiss()
        }
    }
}

private extension ViewController {
    func setupCaptureSession() {
        let captureSession = AVCaptureSession()
        
        if let captureDevice = AVCaptureDevice.default(for: AVMediaType.video) {
            do {
                let input = try AVCaptureDeviceInput(device: captureDevice)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
            } catch let error {
                print("Failed to set input device with error: \(error)")
            }
            
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }
            
            let cameraLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            cameraLayer.frame = self.view.frame
            cameraLayer.videoGravity = .resizeAspectFill
            self.view.layer.addSublayer(cameraLayer)
            self.view.bringSubviewToFront(logoDescription)
            
            captureSession.startRunning()
            capturePhoto()
        }
    }
    
    func capturePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        if let photoPreviewType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
            photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoPreviewType]
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
}

private extension ViewController {
    func updateClassifications(for image: UIImage) {
        let orientation = getCGOrientationFromUIImage(image)

        guard let ciImage = CIImage(image: image)
        else { fatalError("Unable to create \(CIImage.self) from \(image).") }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                fatalError("Failed to preform classification: \(error.localizedDescription)")
            }
        }
    }
    
    func processClassifications(for request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            
            guard let classifications = request.results as? [VNClassificationObservation], !classifications.isEmpty else {
                return
            }
            
            let classification = classifications.max {a, b in a.confidence < b.confidence }

            if let confidence = classification?.confidence, confidence > 0.6,
               let identifier = classification?.identifier {
                self.logoDescription.setTitle(identifier, for: .normal)
            } else {
                self.logoDescription.setTitle("No results found", for: .normal)
            }
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .milliseconds(1000)) {
                self.capturePhoto()
            }
        }
    }
}

private extension ViewController {
    func getCGOrientationFromUIImage(_ image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .left:
            return .left
        case .right:
            return .right
        case .up:
            return .up
        case .downMirrored:
            return .downMirrored
        case .leftMirrored:
            return .leftMirrored
        case .rightMirrored:
            return .rightMirrored
        case .upMirrored:
            return .upMirrored
        default:
            return .down
        }
    }
}

private extension ViewController {
    @objc func handleDismiss() {
        DispatchQueue.main.async {
            self.dismiss(animated: true, completion: nil)
        }
    }
}
