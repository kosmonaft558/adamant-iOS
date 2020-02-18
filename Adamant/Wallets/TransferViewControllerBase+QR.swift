//
//  TransferViewControllerBase+QR.swift
//  Adamant
//
//  Created by Anokhov Pavel on 29.08.2018.
//  Copyright © 2018 Adamant. All rights reserved.
//

import Foundation
import QRCodeReader
import EFQRCode
import AVFoundation
import Photos


// MARK: - QR
extension TransferViewControllerBase {
    func scanQr() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            qrReader.modalPresentationStyle = .overFullScreen
            present(qrReader, animated: true, completion: nil)
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] (granted: Bool) in
                if granted, let qrReader = self?.qrReader {
                    qrReader.modalPresentationStyle = .overFullScreen
                    if Thread.isMainThread {
                        self?.present(qrReader, animated: true, completion: nil)
                    } else {
                        DispatchQueue.main.async {
                            self?.present(qrReader, animated: true, completion: nil)
                        }
                    }
                } else {
                    return
                }
            }
            
        case .restricted:
            let alert = UIAlertController(title: nil, message: String.adamantLocalized.login.cameraNotSupported, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String.adamantLocalized.alert.ok, style: .cancel, handler: nil))
            alert.modalPresentationStyle = .overFullScreen
            present(alert, animated: true, completion: nil)
            
        case .denied:
            let alert = UIAlertController(title: nil, message: String.adamantLocalized.login.cameraNotAuthorized, preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: String.adamantLocalized.alert.settings, style: .default) { _ in
                DispatchQueue.main.async {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                    }
                }
            })
            
            alert.addAction(UIAlertAction(title: String.adamantLocalized.alert.cancel, style: .cancel, handler: nil))
            alert.modalPresentationStyle = .overFullScreen
            present(alert, animated: true, completion: nil)
        }
    }
    
    func loadQr() {
        let presenter: () -> Void = { [weak self] in
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.allowsEditing = false
            picker.sourceType = .photoLibrary
            picker.modalPresentationStyle = .overFullScreen
            // overrideUserInterfaceStyle is available with iOS 13
            if #available(iOS 13.0, *) {
                // Always adopt a light interface style.
                picker.overrideUserInterfaceStyle = .light
            }
            self?.present(picker, animated: true, completion: nil)
        }
        
        if #available(iOS 11.0, *) {
            presenter()
        } else {
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                presenter()
                
            case .notDetermined:
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized {
                        presenter()
                    }
                }
                
            case .restricted, .denied:
                dialogService.presentGoToSettingsAlert(title: nil, message: String.adamantLocalized.login.photolibraryNotAuthorized)
            }
        }
    }
}

// MARK: - ButtonsStripeViewDelegate
extension TransferViewControllerBase: ButtonsStripeViewDelegate {
    func buttonsStripe(_ stripe: ButtonsStripeView, didTapButton button: StripeButtonType) {
        switch button {
        case .qrCameraReader:
            scanQr()
            
        case .qrPhotoReader:
            loadQr()
            
        default:
            return
        }
    }
}

// MARK: - UIImagePickerControllerDelegate
extension TransferViewControllerBase: UINavigationControllerDelegate, UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        dismiss(animated: true, completion: nil)
        
        guard let image = info[.originalImage] as? UIImage else {
            return
        }
        
        if let cgImage = image.toCGImage(), let codes = EFQRCode.recognize(image: cgImage), codes.count > 0 {
            for aCode in codes {
                if handleRawAddress(aCode) {
                    return
                }
            }
            
            dialogService.showWarning(withMessage: String.adamantLocalized.newChat.wrongQrError)
        } else {
            dialogService.showWarning(withMessage: String.adamantLocalized.login.noQrError)
        }
    }
}

// MARK: - QRCodeReaderViewControllerDelegate
extension TransferViewControllerBase: QRCodeReaderViewControllerDelegate {
    func reader(_ reader: QRCodeReaderViewController, didScanResult result: QRCodeReaderResult) {
        if handleRawAddress(result.value) {
            dismiss(animated: true, completion: nil)
        } else {
            dialogService.showWarning(withMessage: String.adamantLocalized.newChat.wrongQrError)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                reader.startScanning()
            }
        }
    }
    
    func readerDidCancel(_ reader: QRCodeReaderViewController) {
        reader.dismiss(animated: true, completion: nil)
    }
}
