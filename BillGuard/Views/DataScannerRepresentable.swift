//
//  DataScannerRepresentable.swift
//  BillGuard
//
//  UIViewControllerRepresentable wrapper for VisionKit DataScannerViewController
//

import SwiftUI
import VisionKit

@MainActor
struct DataScannerRepresentable: UIViewControllerRepresentable {
    
    let onTextTapped: (String) -> Void
    let onError: (Error) -> Void
    
    @Binding var isScanning: Bool
    
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }
    
    static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if isScanning {
            if !uiViewController.isScanning {
                try? uiViewController.startScanning()
            }
        } else {
            if uiViewController.isScanning {
                uiViewController.stopScanning()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onTextTapped: onTextTapped, onError: onError)
    }
    
    @MainActor
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        
        let onTextTapped: (String) -> Void
        let onError: (Error) -> Void
        
        init(onTextTapped: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
            self.onTextTapped = onTextTapped
            self.onError = onError
        }
        
        nonisolated func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            let transcript: String
            switch item {
            case .text(let text):
                transcript = text.transcript
            default:
                return
            }
            
            Task { @MainActor [weak self] in
                self?.onTextTapped(transcript)
            }
        }
        
        // These delegate methods are now no-ops - we only process tapped items
        nonisolated func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // No automatic processing - user must tap to select
        }
        
        nonisolated func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // No automatic processing - user must tap to select
        }
        
        nonisolated func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            Task { @MainActor [weak self] in
                self?.onError(error)
            }
        }
    }
}

// MARK: - Scanner Availability Check

struct ScannerAvailabilityView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Scanner Not Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your device doesn't support text scanning, or camera access is not available.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
