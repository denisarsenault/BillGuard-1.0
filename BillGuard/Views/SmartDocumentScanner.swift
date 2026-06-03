//
//  SmartDocumentScanner.swift
//  BillGuard
//
//  Smart document scanner with alignment guides, edge detection, and auto-capture
//

import SwiftUI
import AVFoundation
import Vision
import ImageIO
import CoreImage

// MARK: - Smart Document Scanner View

struct SmartDocumentScanner: View {
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    @State private var documentDetected = false
    @State private var documentCorners: [CGPoint] = []
    @State private var alignmentStatus: AlignmentStatus = .searching
    @State private var stabilityCounter = 0
    @State private var lastStableCorners: [CGPoint] = []
    @State private var showFlash = false
    @State private var capturedPreview: UIImage?
    @State private var showingPreview = false
    @State private var croppedEdges: Set<CroppedEdge> = []
    @State private var cameraReady = false
    /// Tracks when a document was first detected (kept for potential future use).
    @State private var detectionStartTime: Date? = nil

    // ── Low-light detection ──────────────────────────────────────────────────
    /// True when sampled frame brightness is below the warning threshold.
    @State private var isLowLight = false
    /// True when the user has been shown the low-light prompt this session.
    @State private var lowLightPromptShown = false
    /// Controls the actionable low-light sheet.
    @State private var showingLowLightPrompt = false
    /// Whether the torch is currently on.
    @State private var torchActive = false
    /// Drives the pulsing animation on the capture button in low-light.
    @State private var lowLightPulse = false
    
    enum CroppedEdge: Hashable {
        case top, bottom, left, right
    }
    
    enum AlignmentStatus {
        case searching
        case detected
        case cropped        // Document is partially off-screen
        case almostAligned
        case aligned
        case capturing
        case captured
        
        var message: String {
            switch self {
            case .searching: return "Position document in frame"
            case .detected: return "Document detected - move closer"
            case .cropped: return "⚠️ Document is cut off — reposition!"
            case .almostAligned: return "Almost there - hold steady"
            case .aligned: return "Perfect! Hold still..."
            case .capturing: return "Capturing..."
            case .captured: return "Captured!"
            }
        }
        
        var color: Color {
            switch self {
            case .searching: return .white
            case .detected: return .yellow
            case .cropped: return .yellow
            case .almostAligned: return .orange
            case .aligned, .capturing, .captured: return .green
            }
        }
        
        var icon: String {
            switch self {
            case .searching: return "doc.viewfinder"
            case .detected: return "doc"
            case .cropped: return "exclamationmark.triangle.fill"
            case .almostAligned: return "arrow.up.and.down.and.arrow.left.and.right"
            case .aligned: return "checkmark.circle"
            case .capturing: return "camera.fill"
            case .captured: return "checkmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Black background (shows immediately while camera loads)
            Color.black.ignoresSafeArea()
            
            // Camera Preview
            DocumentCameraPreview(
                documentDetected: $documentDetected,
                documentCorners: $documentCorners,
                isLowLight: $isLowLight,
                lowLightPromptShown: $lowLightPromptShown,
                showingLowLightPrompt: $showingLowLightPrompt,
                showingPreview: $showingPreview,
                onStableDocument: handleStableDocument,
                onCameraReady: { cameraReady = true }
            )
            .ignoresSafeArea()
            
            // Loading indicator while camera initializes
            if !cameraReady {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.3)
                    Text("Starting camera…")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            // Overlay
            VStack(spacing: 0) {
                // Top bar
                topBar

                // Low-light warning banner
                if isLowLight && !torchActive {
                    lowLightBanner
                }

                Spacer()

                // Document frame guide
                documentFrameGuide

                Spacer()

                // Status and controls
                bottomControls
            }
            
            // Cropped edge flashing warning overlay
            if alignmentStatus == .cropped && !croppedEdges.isEmpty {
                CroppedEdgeFlashOverlay(croppedEdges: croppedEdges)
            }
            
            // Flash effect
            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // Processing overlay — covers camera from capture through to the moment
            // the preview screen is visible. Stays up for the entire .captured state
            // so there is no camera flash during the fullScreenCover transition.
            if alignmentStatus == .capturing || alignmentStatus == .captured {
                ProcessingOverlayView()
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeIn(duration: 0.3)))
            }
        }
        .onChange(of: documentCorners) { _, newCorners in
            updateAlignmentStatus(corners: newCorners)
        }
        // Low-light prompt sheet
        .sheet(isPresented: $showingLowLightPrompt) {
            LowLightPromptSheet(
                onEnableFlash: {
                    showingLowLightPrompt = false
                    torchActive = true
                    NotificationCenter.default.post(name: .setTorch, object: true)
                },
                onDismiss: {
                    showingLowLightPrompt = false
                }
            )
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showingPreview) {
            DocumentPreviewView(
                image: $capturedPreview,
                onAccept: {
                    capturedImage = capturedPreview
                    dismiss()
                },
                onRetake: {
                    capturedPreview = nil
                    showingPreview = false
                    alignmentStatus = .searching
                    stabilityCounter = 0
                    lastStableCorners = []
                    documentDetected = false
                    croppedEdges = []
                    detectionStartTime = nil
                }
            )
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: alignmentStatus.icon)
                Text(alignmentStatus.message)
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(alignmentStatus.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.6))
            .cornerRadius(20)
            
            Spacer()
            
            // Placeholder for symmetry
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding()
    }
    
    // MARK: - Low-Light Banner

    private var lowLightBanner: some View {
        Button {
            if !lowLightPromptShown {
                lowLightPromptShown = true
                showingLowLightPrompt = true
            } else {
                // Subsequent taps toggle torch directly
                torchActive.toggle()
                NotificationCenter.default.post(name: .setTorch, object: torchActive)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.slash.fill")
                    .foregroundColor(.yellow)
                Text(lowLightPromptShown ? "Tap to toggle torch" : "Too dark — tap for options")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: isLowLight)
    }

    // MARK: - Document Frame Guide
    
    private var documentFrameGuide: some View {
        GeometryReader { geometry in
            let frameWidth = geometry.size.width * 0.85
            let frameHeight = geometry.size.height * 0.90  // Fill top to bottom
            let frameX = (geometry.size.width - frameWidth) / 2
            let frameY = (geometry.size.height - frameHeight) / 2
            
            ZStack {
                // Dimmed overlay outside the frame
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addRoundedRect(
                        in: CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight),
                        cornerSize: CGSize(width: 12, height: 12)
                    )
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                
                // Frame border
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        alignmentStatus == .cropped ? Color.yellow :
                        (alignmentStatus == .aligned || alignmentStatus == .capturing ?
                        Color.green : (documentDetected ? Color.yellow : Color.white.opacity(0.8))),
                        lineWidth: (alignmentStatus == .aligned || alignmentStatus == .cropped) ? 4 : 2
                    )
                    .frame(width: frameWidth, height: frameHeight)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                // Corner guides
                cornerGuides(frameX: frameX, frameY: frameY, frameWidth: frameWidth, frameHeight: frameHeight)
            }
        }
    }
    
    private func cornerGuides(frameX: CGFloat, frameY: CGFloat, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
        let cornerLength: CGFloat = 30
        let cornerColor = alignmentStatus == .aligned ? Color.green :
                          (alignmentStatus == .cropped ? Color.yellow : Color.white)
        
        return ZStack {
            // Top-left corner
            CornerGuide(length: cornerLength, color: cornerColor)
                .position(x: frameX + cornerLength/2, y: frameY + cornerLength/2)
            
            // Top-right corner
            CornerGuide(length: cornerLength, color: cornerColor)
                .rotationEffect(.degrees(90))
                .position(x: frameX + frameWidth - cornerLength/2, y: frameY + cornerLength/2)
            
            // Bottom-left corner
            CornerGuide(length: cornerLength, color: cornerColor)
                .rotationEffect(.degrees(-90))
                .position(x: frameX + cornerLength/2, y: frameY + frameHeight - cornerLength/2)
            
            // Bottom-right corner
            CornerGuide(length: cornerLength, color: cornerColor)
                .rotationEffect(.degrees(180))
                .position(x: frameX + frameWidth - cornerLength/2, y: frameY + frameHeight - cornerLength/2)
        }
    }
    
    // MARK: - Bottom Controls
    
    private var bottomControls: some View {
        VStack(spacing: 20) {
            // Tips
            if alignmentStatus == .searching {
                HStack(spacing: 20) {
                    tipItem(icon: "lightbulb.fill", text: "Good lighting")
                    tipItem(icon: "rectangle.portrait", text: "Flat surface")
                    tipItem(icon: "hand.raised.fill", text: "Hold steady")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            } else if alignmentStatus == .cropped {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Move back so the entire document is visible")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.4))
                .cornerRadius(10)
            }
            
            // Manual capture button
            HStack(spacing: 40) {
                // Photo library button
                Button {
                    // Would open photo library
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                
                // Capture button
                // In low light without torch: show the torch prompt instead of capturing.
                Button {
                    if isLowLight && !torchActive {
                        // Only show if not already showing (prevent duplicate sheet)
                        if !showingLowLightPrompt {
                            showingLowLightPrompt = true
                        }
                    } else {
                        // Dismiss any open sheet before capture to avoid sheet conflict
                        if showingLowLightPrompt {
                            showingLowLightPrompt = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                manualCapture()
                            }
                        } else {
                            manualCapture()
                        }
                    }
                } label: {
                    ZStack {
                        // Outer ring — yellow pulsing in low light, white/green otherwise
                        Circle()
                            .stroke(
                                isLowLight && !torchActive ? Color.yellow :
                                (documentDetected ? Color.white : Color.white.opacity(0.4)),
                                lineWidth: isLowLight && !torchActive ? 3 : 4
                            )
                            .frame(width: 70, height: 70)
                            .overlay(
                                // Pulsing yellow ring when dark
                                Circle()
                                    .stroke(Color.yellow.opacity(0.4), lineWidth: 6)
                                    .frame(width: 70, height: 70)
                                    .scaleEffect(lowLightPulse ? 1.18 : 1.0)
                                    .opacity(isLowLight && !torchActive ? 1 : 0)
                                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                                               value: lowLightPulse)
                            )

                        // Inner fill — yellow/warning in low light
                        Circle()
                            .fill(
                                isLowLight && !torchActive ? Color.yellow.opacity(0.85) :
                                (alignmentStatus == .aligned ? Color.green :
                                 (documentDetected ? Color.white : Color.white.opacity(0.4)))
                            )
                            .frame(width: 58, height: 58)

                        if alignmentStatus == .capturing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        } else if isLowLight && !torchActive {
                            // Torch icon in button when dark
                            Image(systemName: "lightbulb.slash.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.black.opacity(0.8))
                        }
                    }
                }
                .disabled(alignmentStatus == .capturing)
                .onAppear { lowLightPulse = true }
                
                // Torch toggle
                Button {
                    torchActive.toggle()
                    NotificationCenter.default.post(name: .setTorch, object: torchActive)
                } label: {
                    Image(systemName: torchActive ? "bolt.fill" : "bolt.slash.fill")
                        .font(.title2)
                        .foregroundColor(torchActive ? .yellow : .white)
                        .frame(width: 50, height: 50)
                        .background(torchActive ? Color.yellow.opacity(0.25) : Color.white.opacity(0.2))
                        .clipShape(Circle())
                        .animation(.easeInOut(duration: 0.15), value: torchActive)
                }
            }
            
            Text(isLowLight && !torchActive
                 ? "Low light — tap button to enable torch"
                 : "Tap the button to capture")
                .font(.caption)
                .foregroundColor(isLowLight && !torchActive ? .yellow : .white.opacity(0.6))
                .animation(.easeInOut(duration: 0.3), value: isLowLight)
        }
        .padding(.bottom, 40)
    }
    
    private func tipItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
    }
    
    // MARK: - Alignment Logic
    
    private func updateAlignmentStatus(corners: [CGPoint]) {
        // CRITICAL: Stop all updates once capture is in progress
        guard alignmentStatus != .capturing && alignmentStatus != .captured else { return }

        // No document detected at all
        guard corners.count == 4 else {
            // Decay counter slowly — 1 missing frame shouldn't wipe progress
            if stabilityCounter > 0 {
                stabilityCounter = max(stabilityCounter - 1, 0)
            }
            if stabilityCounter == 0 {
                alignmentStatus = .searching
                documentDetected = false
                detectionStartTime = nil
            }
            croppedEdges = []
            return
        }

        // Document detected
        documentDetected = true

        // --- Cropped Edge Detection ---
        let edgeMargin: CGFloat = 0.005
        var detectedCroppedEdges: Set<CroppedEdge> = []
        for corner in corners {
            if corner.x < edgeMargin { detectedCroppedEdges.insert(.left) }
            if corner.x > (1.0 - edgeMargin) { detectedCroppedEdges.insert(.right) }
            if corner.y < edgeMargin { detectedCroppedEdges.insert(.top) }
            if corner.y > (1.0 - edgeMargin) { detectedCroppedEdges.insert(.bottom) }
        }
        croppedEdges = detectedCroppedEdges

        if !detectedCroppedEdges.isEmpty {
            alignmentStatus = .cropped
            stabilityCounter = min(stabilityCounter, 2)
            detectionStartTime = nil
            return
        }

        // --- Stability check ---
        let stable = isStable(newCorners: corners)
        if stable {
            stabilityCounter += 1
        } else {
            // Only decrement if we're bouncing low (< 4).
            // Once progress is built up, a single noisy frame shouldn't tear it down.
            if stabilityCounter < 4 {
                stabilityCounter = max(stabilityCounter - 1, 0)
            }
            // If counter is >= 4 (almostAligned or better), ignore single bad frames.
        }

        lastStableCorners = corners

        // --- Normal state transitions (tap-only capture — no auto-fire) ---
        if stabilityCounter > 5 {
            alignmentStatus = .aligned
        } else if stabilityCounter > 2 {
            alignmentStatus = .almostAligned
        } else {
            alignmentStatus = .detected
        }
    }

    private func isStable(newCorners: [CGPoint]) -> Bool {
        guard lastStableCorners.count == 4, newCorners.count == 4 else { return true }

        let threshold: CGFloat = 0.06  // Slightly more forgiving than 0.05
        for i in 0..<4 {
            let dx = abs(newCorners[i].x - lastStableCorners[i].x)
            let dy = abs(newCorners[i].y - lastStableCorners[i].y)
            if dx > threshold || dy > threshold {
                return false
            }
        }
        return true
    }
    
    // MARK: - Capture
    
    private func handleStableDocument(image: UIImage) {
        guard alignmentStatus == .capturing || alignmentStatus == .aligned else { return }
        
        alignmentStatus = .capturing
        
        withAnimation(.easeInOut(duration: 0.3)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) { self.showFlash = false }
        }
        
        // Snapshot the live-detected corners RIGHT NOW on the main thread before
        // entering the detached Task. These are the corners the live viewfinder already
        // validated -- we will use them directly rather than re-detecting from scratch.
        let rawCorners = lastStableCorners  // [CGPoint] in video-frame 0-1 space, snapshot now

        // ── Coordinate-space correction ──────────────────────────────────────────
        // Vision detects corners in 0-1 normalised space relative to the full video
        // buffer (portrait: 1080 x 1920 for the .high preset, aspect ratio 9/16).
        //
        // The preview layer uses .resizeAspectFill to fill the screen, which is
        // narrower in portrait (e.g. 390/844 ≈ 0.462) than the video (0.5625).
        // To fill the screen height, the video is scaled so that its width EXCEEDS
        // the screen width, and the surplus is cropped equally from both sides.
        //
        // After cropToPreviewBounds, the still photo has the same AR as the screen.
        // So the corner coords must be remapped from [cropFrac … 1-cropFrac] in video
        // space to [0 … 1] in the cropped-photo space, otherwise the left/right edges
        // are shifted inward by the crop fraction.
        let screenBounds = UIScreen.main.bounds
        let screenAR = screenBounds.width / screenBounds.height

        // ── Corner coordinate remapping: video space → cropped-photo space ───────
        //
        // Vision corners are in 9:16 video frame space (portrait, Y-down, 0-1).
        // The still photo is 3:4 (AR=0.75), which is WIDER than the 9:16 video
        // (AR=0.5625) — the photo captures more scene content horizontally.
        //
        // Two crops must be composed:
        //
        // Stage 1 — video frame is a CENTER STRIP of the full photo sensor:
        //   video_fraction_of_photo_width = videoAR / photoAR = 0.5625 / 0.75 = 0.75
        //   offset_in_photo = (1 - 0.75) / 2 = 0.125
        //   photo_x = 0.125 + video_x * 0.75
        //
        // Stage 2 — cropToPreviewBounds crops the photo to screen AR:
        //   photoAR (0.75) > screenAR (~0.462) → left/right trimmed
        //   photo_crop_frac = (photoAR - screenAR) / (2 * photoAR)
        //   cropped_photo_x = (photo_x - photo_crop_frac) / (1 - 2 * photo_crop_frac)
        //
        // Y needs no adjustment: both video and photo span the full sensor height
        // in portrait orientation, so vision_y maps directly to cropped_photo_y.

        let videoPortraitAR: CGFloat = 1080.0 / 1920.0   // 9/16 = 0.5625
        let photoPortraitAR: CGFloat = 3.0 / 4.0          // 3/4  = 0.75

        func remapCorners(_ corners: [CGPoint]) -> [CGPoint] {
            guard corners.count == 4 else { return corners }

            // Stage 1: video → photo
            let vFrac   = videoPortraitAR / photoPortraitAR       // 0.75
            let vOffset = (1.0 - vFrac) / 2.0                     // 0.125

            // Stage 2: photo → cropped-photo (cropToPreviewBounds result)
            let photoCropFrac: CGFloat
            if photoPortraitAR > screenAR {
                photoCropFrac = (photoPortraitAR - screenAR) / (2.0 * photoPortraitAR)
            } else {
                photoCropFrac = 0
            }
            let photoVisible = 1.0 - 2.0 * photoCropFrac

            return corners.map { p in
                let photoX   = vOffset + p.x * vFrac
                let croppedX = photoVisible > 0 ? (photoX - photoCropFrac) / photoVisible : photoX
                return CGPoint(x: min(1, max(0, croppedX)), y: p.y)
            }
        }

        let adjustedCorners = remapCorners(rawCorners)

        // Corners pass through unchanged — no Y adjustment needed.
        // iPhone 4:3 photo (AR=0.75) is wider than screen (AR≈0.46) in portrait,
        // so cropToPreviewBounds only trims left/right, never top/bottom.
        let finalCorners = adjustedCorners

        struct ImageBox:   @unchecked Sendable { let image: UIImage }
        struct ScreenBox:  @unchecked Sendable { let bounds: CGRect }
        struct CornersBox: @unchecked Sendable { let corners: [CGPoint] }
        let box      = ImageBox(image: image)
        let screen   = ScreenBox(bounds: screenBounds)
        let cornersB = CornersBox(corners: finalCorners)

        Task.detached(priority: .userInitiated) {
            // Step 0: Normalize orientation FIRST -- camera may deliver .right/.left
            let normalized: UIImage
            if box.image.imageOrientation != .up,
               let normalizedCG = DocumentImageEnhancer.normalizeOrientation(box.image) {
                normalized = UIImage(cgImage: normalizedCG)
            } else {
                normalized = box.image
            }

            // Step 0b: Check captured image brightness.
            // The live-preview sampler may have missed a dark frame if the user
            // tapped before 5 frames elapsed, or the scene darkened after the
            // last sample. Check the actual captured CGImage here as a safety net.
            if let cg = normalized.cgImage {
                let luma = DocumentImageEnhancer.estimateCapturedBrightness(cg)
                if luma < 0.35 {
                    await MainActor.run {
                        self.isLowLight = true
                        // Don't open the low-light sheet here — we're inside the
                        // capture pipeline and are about to show the preview fullScreenCover.
                        // Opening a sheet now would conflict and hang the UI.
                        // The Review Scan screen shows its own "Low Light Detected" banner.
                    }
                }
            }

            // Step 1: Crop the full-sensor photo to match what the user saw in the preview.
            // After this crop the photo's AR == screenAR, and the adjusted corners (which
            // are now in screen-space 0-1) map directly onto it.
            let previewCropped = DocumentImageEnhancer.cropToPreviewBounds(normalized, screenBounds: screen.bounds)

            // Step 2: Perspective-correct using the remapped live corners, then
            // run twoPass on the result to extract any sub-document within it.
            //
            // WHY CHAIN BOTH?
            // The live viewfinder can lock onto the monitor bezel (the largest
            // visible rectangle) rather than the document itself. When shooting a
            // tilted screen, live-corners correction then produces a perspective-
            // straightened view of the entire desktop — which still contains the
            // document as an inner rectangle. twoPass then finds and extracts it.
            //
            // Step 2: Document extraction strategy
            //
            // The live viewfinder corners are in 9:16 video space. Mapping them to
            // the 4:3 photo space requires knowing the exact video-to-photo sensor
            // crop ratio, which varies by iPhone model and camera mode. Analytical
            // mapping is unreliable — if the ratio is off by even a few percent,
            // CIPerspectiveCorrection crops INSIDE the document, leaving background.
            //
            // Robust approach: use the live corners only to CONFIRM a document was
            // detected, then let Vision find precise corners on the actual photo pixels
            // (where the coordinate space is well-defined and camera-model-agnostic).
            //
            // Three-tier fallback:
            //  1. Vision on previewCropped (accurate photo-space corners)
            //  2. twoPass + finalize (handles screen-within-screen)
            //  3. textUnionCrop (last resort for low-contrast scenes)
            let corrected: UIImage

            let documentDetectedByLiveScanner = cornersB.corners.count == 4

            // Tier 1: Vision detection on the actual captured photo
            if let visionCorrected = DocumentImageEnhancer.perspectiveCorrectedImage(
                    previewCropped, corners: nil) {
                let inputPx  = previewCropped.size.width * previewCropped.size.height
                let outputPx = visionCorrected.size.width * visionCorrected.size.height
                let ratio    = inputPx > 0 ? outputPx / inputPx : 1.0
                #if DEBUG
                print("capture: Vision on photo ✅  ratio=\(String(format:"%.0f%%", ratio*100))  liveDetected=\(documentDetectedByLiveScanner)")
                #endif
                if ratio < 0.95 {
                    // Tier 1 found a boundary — but on a screen capture this is often
                    // the WINDOW/screen rectangle, leaving title-bar/toolbar chrome
                    // above the document. Iteratively re-run document segmentation to
                    // peel down to the page itself, cropping off everything outside the
                    // document's margins. Segmentation finds the page silhouette (a dark
                    // header stays included), so this trims chrome WITHOUT the edge-based
                    // header-cut risk that finalizeDocumentCrop carries.
                    var working = visionCorrected
                    for pass in 0..<2 {
                        guard let inner = DocumentImageEnhancer.perspectiveCorrectedImage(working, corners: nil) else { break }
                        let workPx  = working.size.width * working.size.height
                        let innerPx = inner.size.width * inner.size.height
                        let innerRatio = workPx > 0 ? innerPx / workPx : 1.0
                        // Accept only a meaningful shrink (trimmed chrome) that isn't an
                        // over-crop to an inner element (e.g. a table border).
                        if innerRatio < 0.92 && innerRatio > 0.45 {
                            working = inner
                            #if DEBUG
                            print("capture: chrome-trim pass \(pass + 1) → \(String(format:"%.0f%%", innerRatio * 100)) of previous")
                            #endif
                        } else {
                            break
                        }
                    }
                    corrected = working
                } else {
                    // Vision returned near-full image — no clear boundary detected
                    // Fall through to twoPass
                    #if DEBUG
                    print("capture: Vision ratio too large — twoPass")
                    #endif
                    let twoPassResult = DocumentImageEnhancer.twoPassPerspectiveCorrectedImage(
                        previewCropped, pass1Gate: documentDetectedByLiveScanner ? 0.55 : 0.75)
                    let afterFinalize = DocumentImageEnhancer.finalizeDocumentCrop(twoPassResult)
                    let shrink = inputPx > 0 ? (afterFinalize.size.width * afterFinalize.size.height) / inputPx : 1.0
                    if shrink > 0.90, let textCropped = DocumentImageEnhancer.textUnionCrop(previewCropped) {
                        corrected = textCropped
                    } else {
                        corrected = afterFinalize
                    }
                }
            } else {
                // Vision found nothing — twoPass + finalize
                #if DEBUG
                print("capture: Vision failed — twoPass+finalize")
                #endif
                let twoPassResult = DocumentImageEnhancer.twoPassPerspectiveCorrectedImage(
                    previewCropped,
                    pass1Gate: documentDetectedByLiveScanner ? 0.55 : 0.75
                )
                let afterFinalize = DocumentImageEnhancer.finalizeDocumentCrop(twoPassResult)
                let inputPx    = previewCropped.size.width  * previewCropped.size.height
                let shrinkRatio = inputPx > 0 ? (afterFinalize.size.width * afterFinalize.size.height) / inputPx : 1.0

                if shrinkRatio > 0.90,
                   let textCropped = DocumentImageEnhancer.textUnionCrop(previewCropped) {
                    #if DEBUG
                    print("capture: no-corners — pipeline returned near-full image (\(String(format:"%.0f%%", shrinkRatio*100))), using text-union crop ✅")
                    #endif
                    corrected = textCropped
                } else {
                    #if DEBUG
                    print("capture: no-corners path — twoPass + finalize (\(String(format:"%.0f%%", shrinkRatio*100)) of input) ✅")
                    #endif
                    corrected = afterFinalize
                }
            }

            let resultBox = ImageBox(image: corrected)
            await MainActor.run {
                self.capturedPreview = resultBox.image
                self.alignmentStatus = .captured

                // Gate all further sheet presentations — prevents the brightness
                // sampler from re-opening showingLowLightPrompt while we transition.
                self.lowLightPromptShown = true

                // Dismiss low-light sheet if open, then wait for dismissal animation
                // before presenting the fullScreenCover. Presenting both simultaneously
                // causes "only presenting a single sheet" spam and a permanent UI hang.
                if self.showingLowLightPrompt {
                    self.showingLowLightPrompt = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.showingPreview = true
                    }
                } else {
                    self.showingPreview = true
                }
            }
        }
    }
    
    private func manualCapture() {
        // Set capturing FIRST to block alignment updates from overwriting
        alignmentStatus = .capturing
        NotificationCenter.default.post(name: .triggerDocumentCapture, object: nil)
    }
    
}

// MARK: - Cropped Edge Flash Overlay

// MARK: - Processing Overlay View

struct ProcessingOverlayView: View {
    @State private var scanLineOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Dark frosted background
            Color("BrandDeepNavy").opacity(0.92)
            
            // Animated scan line
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color("BrandCyan").opacity(0),
                                Color("BrandCyan").opacity(0.4),
                                Color("BrandCyan").opacity(0.8),
                                Color("BrandCyan").opacity(0.4),
                                Color("BrandCyan").opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .offset(y: scanLineOffset)
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: true)) {
                            scanLineOffset = geo.size.height
                        }
                    }
            }
            
            // Center content
            VStack(spacing: 28) {
                // Animated logo
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color("BrandCyan").opacity(0.5), radius: 20)
                    .scaleEffect(pulse)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulse = 1.08
                        }
                    }
                
                // Spinning ring
                ZStack {
                    Circle()
                        .stroke(Color("BrandCyan").opacity(0.15), lineWidth: 3)
                        .frame(width: 50, height: 50)
                    
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color("BrandCyan"), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }
                
                VStack(spacing: 8) {
                    Text("Processing Document")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Correcting perspective & enhancing...")
                        .font(.subheadline)
                        .foregroundColor(Color("BrandCyan").opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Cropped Edge Flash Overlay

struct CroppedEdgeFlashOverlay: View {
    let croppedEdges: Set<SmartDocumentScanner.CroppedEdge>
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let isVisible = Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            
            GeometryReader { geometry in
                ZStack {
                    // Top edge
                    if croppedEdges.contains(.top) {
                        croppedEdgeBar(
                            width: geometry.size.width,
                            height: 10,
                            x: geometry.size.width / 2,
                            y: 5,
                            isVisible: isVisible
                        )
                        
                        directionArrow(
                            systemName: "arrow.down.circle.fill",
                            x: geometry.size.width / 2,
                            y: 50,
                            isVisible: isVisible
                        )
                    }
                    
                    // Bottom edge
                    if croppedEdges.contains(.bottom) {
                        croppedEdgeBar(
                            width: geometry.size.width,
                            height: 10,
                            x: geometry.size.width / 2,
                            y: geometry.size.height - 5,
                            isVisible: isVisible
                        )
                        
                        directionArrow(
                            systemName: "arrow.up.circle.fill",
                            x: geometry.size.width / 2,
                            y: geometry.size.height - 50,
                            isVisible: isVisible
                        )
                    }
                    
                    // Left edge
                    if croppedEdges.contains(.left) {
                        croppedEdgeBar(
                            width: 10,
                            height: geometry.size.height,
                            x: 5,
                            y: geometry.size.height / 2,
                            isVisible: isVisible
                        )
                        
                        directionArrow(
                            systemName: "arrow.right.circle.fill",
                            x: 50,
                            y: geometry.size.height / 2,
                            isVisible: isVisible
                        )
                    }
                    
                    // Right edge
                    if croppedEdges.contains(.right) {
                        croppedEdgeBar(
                            width: 10,
                            height: geometry.size.height,
                            x: geometry.size.width - 5,
                            y: geometry.size.height / 2,
                            isVisible: isVisible
                        )
                        
                        directionArrow(
                            systemName: "arrow.left.circle.fill",
                            x: geometry.size.width - 50,
                            y: geometry.size.height / 2,
                            isVisible: isVisible
                        )
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
    
    private func croppedEdgeBar(width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, isVisible: Bool) -> some View {
        Rectangle()
            .fill(Color.yellow)
            .frame(width: width, height: height)
            .position(x: x, y: y)
            .opacity(isVisible ? 0.85 : 0.15)
    }
    
    private func directionArrow(systemName: String, x: CGFloat, y: CGFloat, isVisible: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 38, height: 38)
            
            Image(systemName: systemName)
                .font(.system(size: 36))
                .foregroundColor(.yellow)
        }
        .position(x: x, y: y)
        .opacity(isVisible ? 1.0 : 0.2)
    }
}

// MARK: - Corner Guide Shape

struct CornerGuide: View {
    let length: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(color)
                .frame(width: length, height: 4)
                .offset(x: length/2 - 2, y: 0)
            
            // Vertical line
            Rectangle()
                .fill(color)
                .frame(width: 4, height: length)
                .offset(x: 0, y: length/2 - 2)
        }
    }
}

// MARK: - Document Preview View

struct DocumentPreviewView: View {
    @Binding var image: UIImage?
    let onAccept: () -> Void
    let onRetake: () -> Void
    
    @State private var adjustedImage: UIImage?
    @State private var isProcessing = false
    
    // Zoom & pan
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0
    @GestureState private var dragTranslation: CGSize = .zero
    
    private var effectiveZoom: CGFloat { zoom * pinchScale }
    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + dragTranslation.width,
               height: offset.height + dragTranslation.height)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image preview — full-screen zoomable
                GeometryReader { geo in
                    if let img = adjustedImage ?? image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(effectiveZoom)
                            .offset(effectiveOffset)
                            .clipped()
                            .contentShape(Rectangle())
                            // Pinch to zoom
                            .gesture(
                                MagnificationGesture()
                                    .updating($pinchScale) { val, state, _ in state = val }
                                    .onEnded { val in
                                        zoom = min(max(zoom * val, 1.0), 6.0)
                                        if zoom <= 1.0 { offset = .zero }
                                    }
                            )
                            // Pan when zoomed
                            .simultaneousGesture(
                                DragGesture()
                                    .updating($dragTranslation) { val, state, _ in
                                        if zoom > 1.05 || pinchScale > 1.05 {
                                            state = val.translation
                                        }
                                    }
                                    .onEnded { val in
                                        if zoom > 1.05 {
                                            offset.width += val.translation.width
                                            offset.height += val.translation.height
                                            // Clamp
                                            let maxX = geo.size.width * (zoom - 1) / 2
                                            let maxY = geo.size.height * (zoom - 1) / 2
                                            offset.width = min(max(offset.width, -maxX), maxX)
                                            offset.height = min(max(offset.height, -maxY), maxY)
                                        }
                                    }
                            )
                            // Double-tap toggle
                            .onTapGesture(count: 2) {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    if zoom > 1.05 {
                                        zoom = 1.0; offset = .zero
                                    } else {
                                        zoom = 2.5
                                    }
                                }
                            }
                    } else {
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.3)
                            Text("Enhancing scan…")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                
                // Bottom panel: prompt + actions
                VStack(spacing: 12) {
                    // Quality bar
                    if adjustedImage != nil {
                        HStack(spacing: 16) {
                            qualityItem(icon: "checkmark.circle.fill", text: "Aligned", color: .green)
                            qualityItem(icon: "checkmark.circle.fill", text: "Sharp", color: .green)
                            qualityItem(icon: "checkmark.circle.fill", text: "Complete", color: .green)
                        }
                    }
                    
                    // Prompt
                    Text("Is the document clear and readable?")
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Pinch to zoom and verify text is legible")
                        .font(.caption).foregroundColor(.secondary)
                    
                    // Zoom indicator
                    if effectiveZoom > 1.05 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { zoom = 1.0; offset = .zero }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.caption2)
                                Text("\(effectiveZoom, specifier: "%.1f")×").font(.caption2).fontWeight(.bold)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundColor(.accentColor)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            onRetake()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                Text("Retake")
                            }
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color("BrandNavy"))
                            .cornerRadius(12)
                        }
                        
                        Button {
                            if let adjusted = adjustedImage {
                                image = adjusted
                            }
                            onAccept()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Use This Photo")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(
                    Color("BrandDeepNavy")
                        .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
                )
            }
            .navigationTitle("Review Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isProcessing {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .onAppear {
                processImage()
            }
            // Full-screen processing overlay: keeps the scanner's processing screen
            // visible while enhance() runs. Fades out once adjustedImage is ready.
            .overlay {
                if adjustedImage == nil {
                    ProcessingOverlayView()
                        .ignoresSafeArea()
                        .transition(.opacity.animation(.easeOut(duration: 0.35)))
                }
            }
            // Low-light warning: shown at top of Review Scan if captured image is dark
            .safeAreaInset(edge: .top) {
                if imageLooksUnderexposed {
                    HStack(spacing: 10) {
                        Image(systemName: "lightbulb.slash.fill")
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Low Light Detected")
                                .font(.caption).fontWeight(.semibold)
                            Text("Consider retaking with torch or better lighting for best OCR results.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.yellow.opacity(0.5)), alignment: .bottom)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: imageLooksUnderexposed)
        }
    }

    private var imageLooksUnderexposed: Bool {
        guard let img = adjustedImage ?? image,
              let cg  = img.cgImage else { return false }
        return DocumentImageEnhancer.estimateCapturedBrightness(cg) < 0.35
    }

    private func qualityItem(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.caption)
        }
    }
    
    private func processImage() {
        guard let inputImage = image else { return }
        isProcessing = true
        
        Task.detached(priority: .userInitiated) {
            let processed = DocumentImageEnhancer.enhance(inputImage)
            
            await MainActor.run {
                adjustedImage = processed
                isProcessing = false
            }
        }
    }
}

// MARK: - Document Image Enhancer (nonisolated)

enum DocumentImageEnhancer {
    static func enhance(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image),
              let cgFull  = image.cgImage else { return image }

        let context = CIContext()
        var outputImage = ciImage

        // ── Step 1: Deskew ──────────────────────────────────────────────────
        let skewAngle = detectTextSkewAngle(image)
        if abs(skewAngle) > 0.003 {
            let transform = CGAffineTransform(rotationAngle: skewAngle)
            let rotated   = outputImage.transformed(by: transform)
            outputImage   = rotated

            if abs(skewAngle) > 0.017 {
                let angle  = abs(skewAngle)
                let origW  = ciImage.extent.width
                let origH  = ciImage.extent.height
                let cosA   = cos(angle); let sinA = sin(angle)
                let denom  = cosA * cosA - sinA * sinA
                if denom > 0 {
                    let innerW = (origW * cosA - origH * sinA) / denom
                    let innerH = (origH * cosA - origW * sinA) / denom
                    if innerW > 10 && innerH > 10 {
                        let ext   = outputImage.extent
                        let cropX = ext.midX - innerW / 2
                        let cropY = ext.midY - innerH / 2
                        outputImage = outputImage.cropped(
                            to: CGRect(x: cropX, y: cropY, width: innerW, height: innerH))
                    }
                }
            }
        }

        // ── Step 2: Adaptive brightness + contrast ──────────────────────────
        // Measure mean luma of the ORIGINAL captured image (before deskew/crop).
        // Scale up brightness and contrast aggressively for underexposed images.
        let luma        = estimateCapturedBrightness(cgFull)
        let isDark      = luma < 0.35
        let isVeryDark  = luma < 0.20

        // Greyscale + contrast + brightness correction
        if let ccFilter = CIFilter(name: "CIColorControls") {
            ccFilter.setValue(outputImage, forKey: kCIInputImageKey)
            ccFilter.setValue(0.0, forKey: kCIInputSaturationKey)  // greyscale

            if isVeryDark {
                // Very dark (torch on but still dim, or night shooting):
                // heavy brightness lift + aggressive contrast
                ccFilter.setValue(2.0, forKey: kCIInputContrastKey)
                ccFilter.setValue(0.35, forKey: kCIInputBrightnessKey)
            } else if isDark {
                // Moderately dark: noticeable lift
                ccFilter.setValue(1.6, forKey: kCIInputContrastKey)
                ccFilter.setValue(0.18, forKey: kCIInputBrightnessKey)
            } else {
                // Normal / well-lit: standard document enhancement
                ccFilter.setValue(1.15, forKey: kCIInputContrastKey)
                ccFilter.setValue(0.0,  forKey: kCIInputBrightnessKey)
            }

            if let result = ccFilter.outputImage { outputImage = result }
        }

        // ── Step 3: Gamma correction for dark images ─────────────────────────
        // CIGammaAdjust with value < 1.0 brightens midtones non-linearly,
        // recovering detail in shadow areas that a flat brightness lift misses.
        if isDark, let gammaFilter = CIFilter(name: "CIGammaAdjust") {
            gammaFilter.setValue(outputImage, forKey: kCIInputImageKey)
            gammaFilter.setValue(isVeryDark ? 0.45 : 0.65, forKey: "inputPower")
            if let result = gammaFilter.outputImage { outputImage = result }
        }

        // ── Step 4: Sharpen ──────────────────────────────────────────────────
        // Sharpen more aggressively on dark images (noise is less of a concern
        // than readability; text edges need crisp boundaries for OCR).
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(outputImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(isDark ? 0.7 : 0.4, forKey: kCIInputSharpnessKey)
            if let result = sharpenFilter.outputImage { outputImage = result }
        }

        // ── Step 5: Noise reduction for very dark / high-ISO shots ───────────
        if isVeryDark, let noiseFilter = CIFilter(name: "CINoiseReduction") {
            noiseFilter.setValue(outputImage, forKey: kCIInputImageKey)
            noiseFilter.setValue(0.02, forKey: "inputNoiseLevel")
            noiseFilter.setValue(0.40, forKey: "inputSharpness")
            if let result = noiseFilter.outputImage { outputImage = result }
        }

        if let cgOut = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgOut, scale: image.scale, orientation: image.imageOrientation)
        }
        return image
    }
    
    /// Detect the skew angle of text in the image using Vision text recognition.
    /// Returns the angle in radians to rotate the image to correct the skew.
    static func detectTextSkewAngle(_ image: UIImage) -> CGFloat {
        guard let cg = image.cgImage ?? normalizeOrientation(image) else { return 0 }
        
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.minimumTextHeight = 0.01
        
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([request])
        
        guard let observations = request.results, observations.count >= 3 else { return 0 }
        
        var angles: [CGFloat] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first,
                  candidate.string.count >= 3 else { continue }
            
            // Get the quadrilateral bounding box for the full text string
            let fullRange = candidate.string.startIndex..<candidate.string.endIndex
            guard let quad = try? candidate.boundingBox(for: fullRange) else { continue }
            
            let bl = quad.bottomLeft
            let br = quad.bottomRight
            let dx = br.x - bl.x
            let dy = br.y - bl.y
            
            // Skip very narrow observations (less than 5% of image width)
            guard abs(dx) > 0.05 else { continue }
            
            let angle = atan2(dy, dx)
            // Accept near-horizontal text within ±30° (expanded from ±15°).
            // Straight-on photos of tilted screens can have text angles up to ~25°.
            if abs(angle) < 0.52 {
                angles.append(angle)
            }
        }
        
        guard angles.count >= 3 else { return 0 }
        
        // Use median angle (robust against outliers)
        let sorted = angles.sorted()
        let median = sorted[sorted.count / 2]
        
        // Cap correction at ±25° — beyond that, perspective correction should handle it
        let capped = max(-0.436, min(0.436, median))

        // Return negative to correct the skew
        return -capped
    }
    
    // MARK: - Brightness Estimation (shared with capture pipeline)

    /// Fast mean-luma estimate on a CGImage. Samples every 8th pixel of the
    /// green channel. Returns 0–1 (0 = black, 1 = white).
    /// Exposed as `static` so the capture Task can call it without an instance.
    static func estimateCapturedBrightness(_ cgImage: CGImage) -> Float {
        guard let data = cgImage.dataProvider?.data,
              let ptr  = CFDataGetBytePtr(data) else { return 0.5 }
        let width    = cgImage.width
        let height   = cgImage.height
        let bpp      = cgImage.bitsPerPixel / 8
        let rowBytes = cgImage.bytesPerRow
        let step     = 8
        var total: UInt64 = 0
        var count: UInt64 = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let offset = y * rowBytes + x * bpp
                total &+= UInt64(ptr[offset + min(1, bpp - 1)])
                count &+= 1
                x += step
            }
            y += step
        }
        return count > 0 ? Float(total) / Float(count) / 255.0 : 0.5
    }

    // MARK: - Near-rectangular Detection Helpers

    /// Returns true when all four interior angles of the detected quad are within
    /// `toleranceDegrees` of 90°. Used to decide whether CIPerspectiveCorrection
    /// is actually needed (a perfectly rectangular document on a flat surface doesn't
    /// need warping — it just needs a tight crop).
    private static func isNearRectangular(_ observation: VNRectangleObservation,
                                          toleranceDegrees: CGFloat = 12.0) -> Bool {
        // Vision gives corners in normalized image coords (origin bottom-left, Y-up).
        // We just need the angles between adjacent edges — coord system doesn't matter.
        let corners: [CGPoint] = [
            CGPoint(x: observation.topLeft.x,     y: observation.topLeft.y),
            CGPoint(x: observation.topRight.x,    y: observation.topRight.y),
            CGPoint(x: observation.bottomRight.x, y: observation.bottomRight.y),
            CGPoint(x: observation.bottomLeft.x,  y: observation.bottomLeft.y)
        ]

        let tolerance = toleranceDegrees * (.pi / 180.0)

        for i in 0..<4 {
            let prev = corners[(i + 3) % 4]
            let curr = corners[i]
            let next = corners[(i + 1) % 4]

            // Vectors from current corner to its neighbours
            let v1 = CGPoint(x: prev.x - curr.x, y: prev.y - curr.y)
            let v2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)

            let dot    = v1.x * v2.x + v1.y * v2.y
            let mag1   = sqrt(v1.x * v1.x + v1.y * v1.y)
            let mag2   = sqrt(v2.x * v2.x + v2.y * v2.y)
            guard mag1 > 0.001, mag2 > 0.001 else { return false }

            let cosA  = max(-1.0, min(1.0, dot / (mag1 * mag2)))
            let angle = acos(cosA)              // angle at this corner in radians
            let diff  = abs(angle - (.pi / 2)) // deviation from 90°

            if diff > tolerance { return false }
        }
        return true
    }

    /// Crop the image tightly to the detected rectangle's bounding box, then apply a
    /// small inset to remove any background bleed-in around the document edges.
    private static func insetCrop(image: UIImage, observation: VNRectangleObservation) -> UIImage? {
        guard let cg = normalizeOrientation(image) ?? image.cgImage else { return nil }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)

        // Convert Vision bounding box (Y-up, 0-1) → pixel rect (Y-down)
        let bb  = observation.boundingBox
        let px  = bb.minX * w
        let py  = (1.0 - bb.maxY) * h
        let pw  = bb.width  * w
        let ph  = bb.height * h

        // Small additional inset (0.5%) to remove any faint background fringe
        let insetX = pw * 0.005
        let insetY = ph * 0.005
        let cropRect = CGRect(x: px + insetX, y: py + insetY,
                              width: pw - insetX * 2, height: ph - insetY * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cropped = cg.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    // MARK: - Preview Bounds Crop

    
    /// Crop a captured photo to match what the user saw in the camera preview.
    /// The preview uses .resizeAspectFill, which center-crops the camera feed to fill
    /// the screen. The captured photo is the full sensor image (wider). This crops
    /// the photo to the visible area so document detection works on what the user saw.
    static func cropToPreviewBounds(_ image: UIImage, screenBounds: CGRect? = nil) -> UIImage {
        // Normalize orientation first so dimensions are correct
        guard let cg = normalizeOrientation(image) ?? image.cgImage else { return image }
        let photoW = CGFloat(cg.width)
        let photoH = CGFloat(cg.height)
        guard photoW > 0, photoH > 0 else { return image }
        
        let photoAR = photoW / photoH
        
        // Use provided screen bounds (thread-safe) or fall back to main screen
        let screen = screenBounds ?? CGRect(x: 0, y: 0, width: 390, height: 844) // Default iPhone 14 size
        let screenAR = screen.width / screen.height
        
        // Only skip when ARs are essentially identical — even small mismatches
        // shift corner coordinates enough to misplace the document boundary.
        if abs(photoAR - screenAR) < 0.001 { return image }
        
        let cropW: CGFloat
        let cropH: CGFloat
        
        if photoAR > screenAR {
            // Photo is wider than screen → crop sides (most common on iPhone)
            cropH = photoH
            cropW = photoH * screenAR
        } else {
            // Photo is taller than screen → crop top/bottom
            cropW = photoW
            cropH = photoW / screenAR
        }
        
        // Horizontal: center-crop (preview is centered left-right with .resizeAspectFill)
        let cropX = (photoW - cropW) / 2
        let cropY = (photoH - cropH) / 2
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        
        guard let cropped = cg.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped)
    }
    
    // MARK: - Orientation & Perspective Correction
    
    /// Normalize UIImage orientation to .up using pure CoreGraphics (thread-safe).
    /// Falls back through multiple bitmap configurations to handle all camera formats.
    static func normalizeOrientation(_ image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        
        let orientation = image.imageOrientation
        if orientation == .up { return cg }
        
        let rawW = CGFloat(cg.width)
        let rawH = CGFloat(cg.height)
        guard rawW > 0, rawH > 0 else { return nil }
        
        // For left/right rotations, the output dimensions are swapped
        let outputW: CGFloat
        let outputH: CGFloat
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            outputW = rawH
            outputH = rawW
        default:
            outputW = rawW
            outputH = rawH
        }
        
        // Try creating context with multiple bitmap configs (camera formats vary)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapConfigs: [UInt32] = [
            cg.bitmapInfo.rawValue,                                                              // Original
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue, // BGRA
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,     // RGBA
            CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,          // RGBX
            CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,      // XBGR
        ]
        
        var ctx: CGContext?
        for config in bitmapConfigs {
            ctx = CGContext(data: nil, width: Int(outputW), height: Int(outputH),
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: colorSpace, bitmapInfo: config)
            if ctx != nil { break }
        }
        
        guard let context = ctx else {
            #if DEBUG
            print("⚠️ normalizeOrientation: CGContext creation failed for all bitmap configs")
            #endif
            return nil
        }
        
        switch orientation {
        case .down:
            context.translateBy(x: outputW, y: outputH); context.rotate(by: .pi)
        case .left:
            context.translateBy(x: outputW, y: 0); context.rotate(by: .pi / 2)
        case .right:
            context.translateBy(x: 0, y: outputH); context.rotate(by: -.pi / 2)
        case .upMirrored:
            context.translateBy(x: outputW, y: 0); context.scaleBy(x: -1, y: 1)
        case .downMirrored:
            context.translateBy(x: 0, y: outputH); context.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            context.translateBy(x: outputW, y: outputH); context.rotate(by: .pi / 2); context.scaleBy(x: -1, y: 1)
        case .rightMirrored:
            context.rotate(by: -.pi / 2); context.scaleBy(x: -1, y: 1)
        default: break
        }
        
        // Always draw at raw pixel dimensions — the transform handles rotation
        context.draw(cg, in: CGRect(x: 0, y: 0, width: rawW, height: rawH))
        
        return context.makeImage()
    }
    
    // MARK: - Private Detection & Correction Helpers

    // MARK: - Edge-Enhanced Pre-processing

    /// Returns a contrast/edge-boosted version of `cgImage` suitable for
    /// low-contrast boundary detection (e.g. white paper on a light screen).
    ///
    /// Pipeline:
    ///   1. Convert to greyscale
    ///   2. CIColorControls  — boost contrast 3× and lift blacks
    ///   3. CIUnsharpMask    — enhance edges so Vision can find the document border
    private static func edgeEnhancedImage(_ cgImage: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: cgImage)
        let ctx = CIContext()

        // Step 1: Greyscale (removes colour noise, helps edge detection)
        guard let greyFilter = CIFilter(name: "CIColorControls") else { return nil }
        greyFilter.setValue(ci, forKey: kCIInputImageKey)
        greyFilter.setValue(0.0, forKey: kCIInputSaturationKey)   // full greyscale
        greyFilter.setValue(1.8, forKey: kCIInputContrastKey)     // boost contrast
        greyFilter.setValue(0.05, forKey: kCIInputBrightnessKey)  // slight lift to brighten darks
        guard let grey = greyFilter.outputImage else { return nil }

        // Step 2: Unsharp mask — exaggerate edges so Vision finds the document boundary
        guard let usm = CIFilter(name: "CIUnsharpMask") else { return nil }
        usm.setValue(grey,  forKey: kCIInputImageKey)
        usm.setValue(4.0,   forKey: kCIInputRadiusKey)      // large radius catches wide edges
        usm.setValue(1.5,   forKey: kCIInputIntensityKey)
        guard let sharpened = usm.outputImage else { return nil }

        return ctx.createCGImage(sharpened, from: sharpened.extent)
    }

    // MARK: - Text-Union Boundary Fallback

    /// Computes the axis-aligned bounding box that encloses ALL recognized text
    /// observations in `cgImage`, then inflates it by `padding` (normalised units)
    /// and returns it as a synthetic `VNRectangleObservation`.
    ///
    /// This is the last-resort fallback for documents where the border has
    /// almost no contrast against the background (e.g. a white PDF displayed
    /// on a white screen) but whose text is still readable by OCR.
    private static func textUnionBoundingRect(cgImage: CGImage) -> VNRectangleObservation? {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel  = .fast   // speed > accuracy here; we only need bbox
        req.minimumTextHeight = 0.008   // catch even small print
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([req])

        guard let observations = req.results, !observations.isEmpty else { return nil }

        // Vision bbox origin is bottom-left, Y-up
        var minX: CGFloat = 1, maxX: CGFloat = 0
        var minY: CGFloat = 1, maxY: CGFloat = 0

        for obs in observations {
            let bb = obs.boundingBox
            minX = min(minX, bb.minX)
            maxX = max(maxX, bb.maxX)
            minY = min(minY, bb.minY)
            maxY = max(maxY, bb.maxY)
        }

        // Reject if the union covers virtually everything (fallback found no real content)
        let unionArea = (maxX - minX) * (maxY - minY)
        guard unionArea > 0.05, unionArea < 0.97 else { return nil }

        // Inflate by 2% on each side to include any borders/padding just outside text
        let pad: CGFloat = 0.02
        let x0 = max(0, minX - pad)
        let y0 = max(0, minY - pad)
        let x1 = min(1, maxX + pad)
        let y1 = min(1, maxY + pad)

        #if DEBUG
        print("📐 textUnion: (\(String(format:"%.2f",x0)),\(String(format:"%.2f",y0)))" +
              "→(\(String(format:"%.2f",x1)),\(String(format:"%.2f",y1)))" +
              "  area=\(String(format:"%.1f%%", unionArea * 100))")
        #endif

        // Synthesise a VNRectangleObservation from the axis-aligned bbox.
        // VNRectangleObservation takes corners in Vision's bottom-left Y-up space.
        let obs = VNRectangleObservation(
            requestRevision: VNRecognizeTextRequestRevision3,
            topLeft:     CGPoint(x: x0, y: y1),
            topRight:    CGPoint(x: x1, y: y1),
            bottomRight: CGPoint(x: x1, y: y0),
            bottomLeft:  CGPoint(x: x0, y: y0)
        )
        return obs
    }

    // MARK: - Best Rectangle Detection (multi-strategy)

    /// Runs Vision document detection on a CGImage using up to four strategies
    /// in order of preference, stopping at the first credible result:
    ///
    ///  1. `VNDetectDocumentSegmentationRequest` on the original image (iOS 15+)
    ///  2. `VNDetectRectanglesRequest`            on the original image
    ///  3. Both detectors again on a contrast/edge-boosted copy of the image
    ///     (catches low-contrast boundaries — white paper on white screen)
    ///  4. Text-union bounding box fallback on the edge-enhanced image
    ///     (last resort when borders are invisible but text is readable)
    ///
    /// Returns the best observation and its normalised bounding-box area (0–1),
    /// or nil when all strategies fail.
    private static func detectBestRectangle(
        cgImage: CGImage,
        minArea: CGFloat = 0.10,
        maxArea: CGFloat = 0.97
    ) -> (observation: VNRectangleObservation, area: CGFloat)? {

        func runDetection(on cg: CGImage) -> VNRectangleObservation? {
            var found: VNRectangleObservation?

            // VNDetectDocumentSegmentationRequest (iOS 15+) — tuned for paper docs
            if #available(iOS 15.0, *) {
                let req     = VNDetectDocumentSegmentationRequest()
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([req])
                found = req.results?.first
            }

            // General rectangle detection fallback
            if found == nil {
                let req = VNDetectRectanglesRequest()
                req.minimumConfidence   = 0.3   // slightly more permissive than before
                req.maximumObservations = 1
                req.minimumAspectRatio  = 0.3
                req.maximumAspectRatio  = 1.0
                req.minimumSize         = 0.10  // was 0.15 — allows smaller detected regions
                req.quadratureTolerance = 40    // was 30 — more tolerant of trapezoid shapes
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([req])
                found = req.results?.first
            }

            return found
        }

        func validate(_ obs: VNRectangleObservation?) -> (observation: VNRectangleObservation, area: CGFloat)? {
            guard let o = obs else { return nil }
            let area = o.boundingBox.width * o.boundingBox.height
            guard area >= minArea, area <= maxArea else { return nil }
            return (o, area)
        }

        // ── Strategy 1 & 2: standard detection on original ────────────────────
        if let result = validate(runDetection(on: cgImage)) {
            #if DEBUG
            print("📐 detectBestRectangle: found on original image (\(String(format:"%.1f%%", result.area * 100)))")
            #endif
            return result
        }

        // ── Strategy 3: retry on contrast/edge-enhanced copy ─────────────────
        // Boosts contrast and sharpens edges so that low-contrast document
        // borders (white PDF on white screen) become detectable.
        if let enhanced = edgeEnhancedImage(cgImage) {
            if let result = validate(runDetection(on: enhanced)) {
                #if DEBUG
                print("📐 detectBestRectangle: found on edge-enhanced image (\(String(format:"%.1f%%", result.area * 100)))")
                #endif
                return result
            }

            // ── Strategy 4: text-union bbox on the enhanced image ─────────────
            // When borders are invisible, recognize all text and use the union
            // of all observation bounding boxes as the document boundary.
            if let textObs = textUnionBoundingRect(cgImage: enhanced) {
                let area = textObs.boundingBox.width * textObs.boundingBox.height
                if area >= minArea, area <= maxArea {
                    #if DEBUG
                    print("📐 detectBestRectangle: using text-union bbox (\(String(format:"%.1f%%", area * 100)))")
                    #endif
                    return (textObs, area)
                }
            }
        }

        #if DEBUG
        print("📐 detectBestRectangle: all strategies failed")
        #endif
        return nil
    }

    /// Applies `CIPerspectiveCorrection` for a known `VNRectangleObservation`.
    private static func applyCIPerspectiveCorrection(
        ciImage: CIImage,
        cgImage: CGImage,
        observation: VNRectangleObservation
    ) -> UIImage? {
        let w = ciImage.extent.width
        let h = ciImage.extent.height

        // Vision uses bottom-left origin (Y-up); CIFilter also uses bottom-left — no flip needed.
        let topLeft     = CGPoint(x: observation.topLeft.x     * w, y: observation.topLeft.y     * h)
        let topRight    = CGPoint(x: observation.topRight.x    * w, y: observation.topRight.y    * h)
        let bottomLeft  = CGPoint(x: observation.bottomLeft.x  * w, y: observation.bottomLeft.y  * h)
        let bottomRight = CGPoint(x: observation.bottomRight.x * w, y: observation.bottomRight.y * h)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage,                        forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft),     forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight),    forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft),  forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let outputCI = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let outputCG = ctx.createCGImage(outputCI, from: outputCI.extent) else { return nil }
        return UIImage(cgImage: outputCG)
    }

    // MARK: - Two-Pass Document Extraction

    /// Two-pass document extraction.
    ///
    /// **Why two passes?**
    /// When the user photographs a screen (monitor/laptop displaying the document),
    /// pass 1 detects the monitor bezel and perspective-corrects to the desktop content.
    /// The actual document is then a sub-rectangle inside that result — pass 2 finds it.
    ///
    /// For normal paper-on-desk shots, pass 1 already lands on the document
    /// (area ≥ 75% of the image) and pass 2 is skipped entirely.
    ///
    /// **Why Vision bbox area, not UIImage pixel size?**
    /// `CIPerspectiveCorrection` outputs a `CIImage` whose pixel dimensions can be
    /// *larger* than the input (the filter doesn't inherently shrink). Comparing
    /// UIImage sizes after the fact gives ratios > 1.0 and breaks threshold logic.
    /// The normalised `boundingBox.width * height` from Vision is always 0–1 and
    /// directly represents "fraction of the input image the rectangle covers."
    ///
    /// - Parameter image: Preview-cropped, orientation-normalised capture.
    /// - Returns: Most tightly cropped document image found. Never nil.
    /// - Parameter pass1Gate: Fraction of the image that pass 1 must cover before
    ///   we skip pass 2. Default 0.75 (paper-on-desk). Pass 0.55 when the input is
    ///   already a perspective-corrected outer frame (e.g. a straightened desktop)
    ///   so we always attempt to dig out the inner document.
    static func twoPassPerspectiveCorrectedImage(
        _ image: UIImage,
        pass1Gate: CGFloat = 0.75
    ) -> UIImage {

        guard let cg1 = normalizeOrientation(image) ?? image.cgImage else { return image }
        guard let (obs1, area1) = detectBestRectangle(cgImage: cg1) else {
            #if DEBUG
            print("📐 twoPass: pass 1 — no rectangle detected, returning original")
            #endif
            return image
        }

        #if DEBUG
        print("📐 twoPass: pass 1 area = \(String(format: "%.1f%%", area1 * 100))  gate=\(String(format: "%.0f%%", pass1Gate * 100))")
        #endif

        // Large + near-rectangular = document already fills the frame.
        // No warp needed — a tight inset crop is sufficient.
        if area1 > 0.88 && isNearRectangular(obs1) {
            #if DEBUG
            print("📐 twoPass: pass 1 large+rectangular → inset crop, done")
            #endif
            return insetCrop(image: image, observation: obs1) ?? image
        }

        let ci1 = CIImage(cgImage: cg1)
        guard let pass1 = applyCIPerspectiveCorrection(ciImage: ci1, cgImage: cg1, observation: obs1) else {
            return image
        }

        // Pass 2 gate: if pass 1 already covered ≥ pass1Gate of the image it found
        // the document directly — no need to dig deeper.
        guard area1 < pass1Gate else {
            #if DEBUG
            print("📐 twoPass: pass 1 area ≥ gate — document found, done")
            #endif
            return pass1
        }

        // Pass 2 ── look for the actual document inside the outer-boundary result
        // (e.g. the medical bill PDF within the perspective-corrected desktop)
        guard let cg2 = normalizeOrientation(pass1) ?? pass1.cgImage else { return pass1 }
        guard let (obs2, area2) = detectBestRectangle(cgImage: cg2) else {
            #if DEBUG
            print("📐 twoPass: pass 2 — no rectangle detected, using pass 1")
            #endif
            return pass1
        }

        #if DEBUG
        print("📐 twoPass: pass 2 area = \(String(format: "%.1f%%", area2 * 100))")
        #endif

        // Large + near-rectangular in pass 2 — the whole corrected view IS the document.
        if area2 > 0.88 && isNearRectangular(obs2) {
            #if DEBUG
            print("📐 twoPass: pass 2 large+rectangular → inset crop on pass 1 result")
            #endif
            return insetCrop(image: pass1, observation: obs2) ?? pass1
        }

        // Only accept pass 2 when it found a genuinely smaller sub-region.
        // If area2 ≥ 75% of pass 1, Vision just re-detected the same boundary
        // (e.g. a thick table border inside the bill) — keep pass 1 instead.
        guard area2 < 0.75 else {
            #if DEBUG
            print("📐 twoPass: pass 2 area ≥ 75%% — too similar to pass 1, using pass 1")
            #endif
            return pass1
        }

        let ci2 = CIImage(cgImage: cg2)
        guard let pass2 = applyCIPerspectiveCorrection(ciImage: ci2, cgImage: cg2, observation: obs2) else {
            return pass1
        }

        #if DEBUG
        print("📐 twoPass: ✅ pass 2 sub-document accepted")
        #endif
        return pass2
    }

    // MARK: - Final Cleanup Crop

    /// Produces a high-contrast edge map of `cgImage` using `CIEdges`.
    ///
    /// Unlike `edgeEnhancedImage` (which boosts contrast for Vision to use directly),
    /// this returns a black image with bright lines at every structural boundary.
    /// `VNDetectRectanglesRequest` on this image finds rectangles defined by real
    /// boundary edges rather than brightness regions — critical when the document and
    /// surrounding content have similar backgrounds (e.g. white paper + white sidebar).
    private static func documentEdgeMap(_ cgImage: CGImage) -> CGImage? {
        let ci  = CIImage(cgImage: cgImage)
        let ctx = CIContext()

        // Grayscale first (removes colour noise)
        guard let grey = CIFilter(name: "CIColorControls") else { return nil }
        grey.setValue(ci,  forKey: kCIInputImageKey)
        grey.setValue(0.0, forKey: kCIInputSaturationKey)
        grey.setValue(1.5, forKey: kCIInputContrastKey)
        guard let greyCI = grey.outputImage else { return nil }

        // Explicit edge-detection — produces bright lines at structural boundaries
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(greyCI, forKey: kCIInputImageKey)
        edgeFilter.setValue(8.0,    forKey: kCIInputIntensityKey)
        guard let edgesCI = edgeFilter.outputImage else { return nil }

        return ctx.createCGImage(edgesCI, from: edgesCI.extent)
    }

    /// Finds the best sub-image rectangle using a multi-candidate rectangle detector.
    ///
    /// Unlike `detectBestRectangle` (which stops at the first valid result),
    /// this asks Vision for up to 6 candidates, then picks the one whose area
    /// falls closest to `targetArea` (default 0.78).  This skips "whole frame"
    /// detections (area ≈ 1.0) and finds the actual document rectangle even when
    /// it nearly fills the frame with only a thin border of non-document content.
    private static func detectSubRectangle(
        cgImage: CGImage,
        minArea:    CGFloat = 0.30,
        maxArea:    CGFloat = 0.93,
        targetArea: CGFloat = 0.78
    ) -> (observation: VNRectangleObservation, area: CGFloat)? {
        let req = VNDetectRectanglesRequest()
        req.minimumConfidence   = 0.25
        req.maximumObservations = 6
        req.minimumAspectRatio  = 0.30
        req.maximumAspectRatio  = 1.00
        req.minimumSize         = 0.20
        req.quadratureTolerance = 45

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([req])

        guard let results = req.results, !results.isEmpty else { return nil }

        // Filter to credible range, then pick the candidate closest to targetArea
        let candidates = results.compactMap { obs -> (VNRectangleObservation, CGFloat)? in
            let area = obs.boundingBox.width * obs.boundingBox.height
            guard area >= minArea, area <= maxArea else { return nil }
            return (obs, area)
        }
        guard !candidates.isEmpty else { return nil }

        let best = candidates.min(by: {
            abs($0.1 - targetArea) < abs($1.1 - targetArea)
        })!

        #if DEBUG
        print("📐 detectSubRect: picked area=\(String(format:"%.1f%%", best.1 * 100)) from \(candidates.count) candidates")
        #endif
        return best
    }

    /// One final tight-crop pass run AFTER the main twoPass pipeline.
    ///
    /// **What it fixes:**
    ///  - Window chrome / app toolbar / sidebar still visible at the edges.
    ///  - Residual slight perspective tilt that survived the main passes.
    ///
    /// **Detection strategy (three attempts, first success wins):**
    ///  1. `documentEdgeMap` + `detectSubRectangle`   — finds boundary lines explicitly;
    ///     best when document and surroundings share similar background colour.
    ///  2. `edgeEnhancedImage` + `detectSubRectangle` — good general-purpose fallback.
    ///  3. `edgeEnhancedImage` + `detectBestRectangle` — last resort.
    ///
    /// **When it skips:**
    ///  - All three attempts return nil
    ///  - CIPerspectiveCorrection returns nil
    // MARK: - Text-Union Crop (standalone fallback)

    /// Runs fast Vision OCR on `image`, unions all text observation bounding boxes,
    /// inflates by 3%, and crops the image to that region.
    ///
    /// This is the last-resort path when rectangle/edge detection both fail
    /// (e.g. white paper on bright white laptop screen with no visible edge).
    /// Even when the border is invisible, text contrast is typically sufficient
    /// for OCR bounding boxes to outline the document content area.
    ///
    /// Returns `nil` when fewer than 5 text observations are found (too little
    /// signal to trust the union boundary — would crop randomly).
    static func textUnionCrop(_ image: UIImage) -> UIImage? {
        guard let cg = normalizeOrientation(image) ?? image.cgImage else { return nil }

        // Try on original first, then on edge-enhanced if too few observations
        func runOCR(on source: CGImage) -> [VNRecognizedTextObservation]? {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel  = .fast
            req.minimumTextHeight = 0.006
            let handler = VNImageRequestHandler(cgImage: source, options: [:])
            try? handler.perform([req])
            let results = req.results ?? []
            return results.count >= 5 ? results : nil
        }

        guard let observations = runOCR(on: cg) ?? runOCR(on: edgeEnhancedImage(cg) ?? cg) else {
            #if DEBUG
            print("📐 textUnionCrop: too few text observations — skipping")
            #endif
            return nil
        }

        var minX: CGFloat = 1, maxX: CGFloat = 0
        var minY: CGFloat = 1, maxY: CGFloat = 0
        for obs in observations {
            let bb = obs.boundingBox   // Vision: origin bottom-left, Y-up
            minX = min(minX, bb.minX); maxX = max(maxX, bb.maxX)
            minY = min(minY, bb.minY); maxY = max(maxY, bb.maxY)
        }

        let unionArea = (maxX - minX) * (maxY - minY)
        guard unionArea > 0.08, unionArea < 0.98 else { return nil }

        // Inflate 3% to include borders/margins outside the text
        let pad: CGFloat = 0.03
        let x0 = max(0, minX - pad); let y0 = max(0, minY - pad)
        let x1 = min(1, maxX + pad); let y1 = min(1, maxY + pad)

        // Convert Vision coords (bottom-left Y-up) to CGImage crop rect (top-left Y-down)
        let w = CGFloat(cg.width); let h = CGFloat(cg.height)
        let cropRect = CGRect(
            x: x0 * w,
            y: (1 - y1) * h,
            width:  (x1 - x0) * w,
            height: (y1 - y0) * h
        ).intersection(CGRect(x: 0, y: 0, width: w, height: h))

        guard let cropped = cg.cropping(to: cropRect) else { return nil }

        #if DEBUG
        print("📐 textUnionCrop: ✅ cropped to \(String(format:"%.1f%%", unionArea*100)) of image")
        #endif
        return UIImage(cgImage: cropped)
    }

    static func finalizeDocumentCrop(_ image: UIImage) -> UIImage {
        guard let cg = normalizeOrientation(image) ?? image.cgImage else { return image }

        // ── Strategy 1: edge-map + multi-candidate rectangle search ──────────
        // CIEdges produces bright lines at structural boundaries. VNDetectRectangles
        // on this finds rectangles formed by edges rather than brightness regions,
        // so it correctly separates the document from a same-colour sidebar.
        var bestObs: VNRectangleObservation?

        if let edgeMap = documentEdgeMap(cg) {
            bestObs = detectSubRectangle(cgImage: edgeMap)?.observation
        }

        // ── Strategy 2: edge-enhanced + multi-candidate ───────────────────────
        if bestObs == nil, let enhanced = edgeEnhancedImage(cg) {
            bestObs = detectSubRectangle(cgImage: enhanced)?.observation
        }

        // ── Strategy 3: edge-enhanced + single-best (original finalise logic) ─
        if bestObs == nil, let enhanced = edgeEnhancedImage(cg) {
            bestObs = detectBestRectangle(cgImage: enhanced, minArea: 0.20, maxArea: 0.93)?.observation
        }

        guard let obs = bestObs else {
            #if DEBUG
            print("📐 finalize: all strategies failed — returning as-is")
            #endif
            return image
        }

        let finalArea = obs.boundingBox.width * obs.boundingBox.height
        #if DEBUG
        print("📐 finalize: applying correction  area=\(String(format:"%.1f%%", finalArea * 100))  nearRect=\(isNearRectangular(obs))")
        #endif

        // Always use CIPerspectiveCorrection: crops to the exact detected quad corners,
        // removing sidebar/toolbar and fixing any residual tilt simultaneously.
        let ci = CIImage(cgImage: cg)
        guard let finalised = applyCIPerspectiveCorrection(ciImage: ci, cgImage: cg,
                                                           observation: obs) else {
            #if DEBUG
            print("📐 finalize: CIPerspectiveCorrection returned nil — returning as-is")
            #endif
            return image
        }

        #if DEBUG
        print("📐 finalize: applied ✅  area=\(String(format: "%.1f%%", finalArea * 100))")
        #endif
        return finalised
    }

    /// Apply perspective correction using known corners or by re-detecting.
    /// `corners` are in screen-normalized coordinates: origin top-left, Y-down (0-1 range).
    /// Order: [topLeft, topRight, bottomRight, bottomLeft]
    static func perspectiveCorrectedImage(_ image: UIImage, corners: [CGPoint]?) -> UIImage? {
        guard let cgImage = normalizeOrientation(image) else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        let w = ciImage.extent.width
        let h = ciImage.extent.height
        
        let topLeft: CGPoint
        let topRight: CGPoint
        let bottomLeft: CGPoint
        let bottomRight: CGPoint
        
        if let c = corners, c.count == 4 {
            topLeft     = CGPoint(x: c[0].x * w, y: (1 - c[0].y) * h)
            topRight    = CGPoint(x: c[1].x * w, y: (1 - c[1].y) * h)
            bottomRight = CGPoint(x: c[2].x * w, y: (1 - c[2].y) * h)
            bottomLeft  = CGPoint(x: c[3].x * w, y: (1 - c[3].y) * h)
        } else {
            var detectedResult: VNRectangleObservation?
            
            if #available(iOS 15.0, *) {
                let docRequest = VNDetectDocumentSegmentationRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([docRequest])
                detectedResult = docRequest.results?.first
            }
            
            if detectedResult == nil {
                let rectRequest = VNDetectRectanglesRequest()
                rectRequest.minimumConfidence = 0.4
                rectRequest.maximumObservations = 1
                rectRequest.minimumAspectRatio = 0.3
                rectRequest.maximumAspectRatio = 1.0
                rectRequest.minimumSize = 0.2
                rectRequest.quadratureTolerance = 30
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([rectRequest])
                detectedResult = rectRequest.results?.first
            }
            
            guard let result = detectedResult else {
                #if DEBUG
                print("📐 perspectiveCorrection: no document detected")
                #endif
                return nil
            }
            
            // Validate detected area
            // <10%  = noise or tiny element — skip
            // >97%  = Vision returned virtually the entire image (detection failed) — skip
            // 92-97% = document fills the frame (straight-on shot of screen/paper) — check rectangularity
            let detectedArea = result.boundingBox.width * result.boundingBox.height
            if detectedArea > 0.97 {
                #if DEBUG
                print("📐 perspectiveCorrection: detected area >\(String(format: "%.1f%%", detectedArea * 100)) — detection returned full image, skipping")
                #endif
                return nil
            }
            if detectedArea < 0.10 {
                #if DEBUG
                print("📐 perspectiveCorrection: detected area too small (\(String(format: "%.1f%%", detectedArea * 100))), skipping")
                #endif
                return nil
            }

            #if DEBUG
            print("📐 perspectiveCorrection: document covers \(String(format: "%.1f%%", detectedArea * 100)) of image")
            #endif

            // When the document fills most of the frame (straight-on / screen shots),
            // the quad is already very close to a rectangle. Applying CIPerspectiveCorrection
            // to a near-rectangular quad can introduce subtle warping. Instead, just do a
            // simple proportional inset crop to trim any background bleeding in around the edges.
            if detectedArea > 0.88 && isNearRectangular(result) {
                #if DEBUG
                print("📐 perspectiveCorrection: large + near-rectangular (\(String(format: "%.1f%%", detectedArea * 100))) — using inset crop")
                #endif
                return insetCrop(image: image, observation: result)
            }
            
            topLeft     = CGPoint(x: result.topLeft.x * w,     y: result.topLeft.y * h)
            topRight    = CGPoint(x: result.topRight.x * w,    y: result.topRight.y * h)
            bottomLeft  = CGPoint(x: result.bottomLeft.x * w,  y: result.bottomLeft.y * h)
            bottomRight = CGPoint(x: result.bottomRight.x * w, y: result.bottomRight.y * h)
        }
        
        // Apply perspective correction to straighten the document
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft),     forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight),    forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomLeft),  forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        
        guard let outputCI = filter.outputImage else { return nil }
        let ctx = CIContext()
        guard let outputCG = ctx.createCGImage(outputCI, from: outputCI.extent) else { return nil }
        return UIImage(cgImage: outputCG)
    }
}

// MARK: - Document Camera Preview (UIViewRepresentable)

struct DocumentCameraPreview: UIViewRepresentable {
    @Binding var documentDetected: Bool
    @Binding var documentCorners: [CGPoint]
    @Binding var isLowLight: Bool
    @Binding var lowLightPromptShown: Bool
    @Binding var showingLowLightPrompt: Bool
    @Binding var showingPreview: Bool
    let onStableDocument: (UIImage) -> Void
    var onCameraReady: (() -> Void)? = nil
    
    func makeUIView(context: Context) -> DocumentCameraUIView {
        let view = DocumentCameraUIView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: DocumentCameraUIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    class Coordinator: NSObject, DocumentCameraDelegate {
        let parent: DocumentCameraPreview
        private var cameraReadyFired = false
        
        init(_ parent: DocumentCameraPreview) {
            self.parent = parent
        }
        
        nonisolated func didDetectDocument(corners: [CGPoint]) {
            Task { @MainActor in
                if !self.cameraReadyFired {
                    self.cameraReadyFired = true
                    self.parent.onCameraReady?()
                }
                self.parent.documentDetected = !corners.isEmpty
                self.parent.documentCorners = corners
            }
        }
        
        nonisolated func didCaptureDocument(image: UIImage) {
            Task { @MainActor in
                self.parent.onStableDocument(image)
            }
        }

        nonisolated func didChangeLightLevel(isLow: Bool) {
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.parent.isLowLight = isLow
                }
                // Auto-show the prompt ONLY when:
                //  • scene first goes dark (not shown yet)
                //  • no capture is in progress
                //  • preview is not already showing
                // Showing a sheet while a fullScreenCover is presenting (or about
                // to present) causes "only presenting a single sheet" spam + UI hang.
                // Use the bindings that DocumentCameraPreview owns.
                // showingLowLightPrompt = a sheet is already up (no second sheet)
                // showingPreview = fullScreenCover is up (no sheet on top of it)
                let sheetAlreadyUp = self.parent.showingLowLightPrompt
                let previewIsUp    = self.parent.showingPreview
                if isLow, !self.parent.lowLightPromptShown, !sheetAlreadyUp, !previewIsUp {
                    self.parent.lowLightPromptShown = true
                    self.parent.showingLowLightPrompt = true
                }
            }
        }
    }
}

// MARK: - Document Camera Delegate Protocol

protocol DocumentCameraDelegate: AnyObject {
    func didDetectDocument(corners: [CGPoint])
    func didCaptureDocument(image: UIImage)
    /// Called whenever the estimated scene brightness crosses the low-light threshold.
    /// `isLow` is true when the scene is too dark for reliable detection.
    func didChangeLightLevel(isLow: Bool)
}

// MARK: - Video Sample Buffer Handler

final class VideoSampleBufferHandler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let onCornersDetected: @Sendable ([CGPoint]) -> Void
    private var lastDetectionTime = Date()
    private var frameCount = 0
    
    // Reuse Vision request to avoid re-allocation cost per frame
    private lazy var docSegmentationRequest: VNRequest? = {
        if #available(iOS 15.0, *) {
            return VNDetectDocumentSegmentationRequest()
        }
        return nil
    }()
    
    private lazy var rectRequest: VNDetectRectanglesRequest = {
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.2
        req.maximumAspectRatio = 1.0
        req.minimumSize = 0.1
        req.maximumObservations = 1
        req.quadratureTolerance = 45
        req.minimumConfidence = 0.3
        return req
    }()
    
    private let onLightLevelChanged: (@Sendable (Bool) -> Void)?
    // Throttle low-light callbacks — only fire when state changes
    private var lastLowLightState: Bool? = nil
    private var brightnessCheckCounter = 0

    init(onCornersDetected: @escaping @Sendable ([CGPoint]) -> Void,
         onLightLevelChanged: (@Sendable (Bool) -> Void)? = nil) {
        self.onCornersDetected     = onCornersDetected
        self.onLightLevelChanged   = onLightLevelChanged
        super.init()
    }

    /// Estimates mean luma of the frame by sampling every 8th pixel of the Y plane.
    /// Returns a value in 0–1 (0 = black, 1 = white). Fast: ~0.2ms on a modern iPhone.
    private func estimateBrightness(from pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 1 }
        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytes  = yPlane.assumingMemoryBound(to: UInt8.self)

        let step = 8   // sample every 8th pixel — fast and statistically solid
        var total: UInt64 = 0
        var count: UInt64 = 0
        var row = 0
        while row < height {
            var col = 0
            while col < width {
                total &+= UInt64(bytes[row * stride + col])
                count &+= 1
                col += step
            }
            row += step
        }
        guard count > 0 else { return 1 }
        return Float(total) / Float(count) / 255.0
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = Date()
        // Throttle: skip frames within 100ms (was 80ms — save ~20% CPU)
        guard now.timeIntervalSince(lastDetectionTime) > 0.10 else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // ── Brightness check (every 5th throttled frame ≈ every 0.5s) ────────
        brightnessCheckCounter += 1
        if brightnessCheckCounter % 5 == 0, let cb = onLightLevelChanged {
            let brightness = estimateBrightness(from: pixelBuffer)
            // Hysteresis: turn ON warning at < 0.35 luma, turn OFF only when > 0.42.
            // This prevents flickering when brightness is right on the edge.
            // 0.35 catches dim indoor shots (like the photo above) not just near-dark.
            let isLow: Bool
            if let prev = lastLowLightState {
                isLow = prev ? brightness < 0.42 : brightness < 0.35
            } else {
                isLow = brightness < 0.35
            }
            if isLow != lastLowLightState {
                lastLowLightState = isLow
                let isLowCopy = isLow
                DispatchQueue.main.async { cb(isLowCopy) }
            }
        }
        
        // Portrait orientation set on video connection → buffer is in portrait space.
        // Tell Vision .up so it interprets the already-portrait buffer correctly.
        // Previously was .right (for raw landscape sensor buffers) — that was wrong
        // once videoOrientation=.portrait was set on the video connection.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            var rectangle: VNRectangleObservation?
            
            // Use cached request objects (saves ~2-5ms per frame from re-allocation)
            if let docRequest = docSegmentationRequest {
                try handler.perform([docRequest])
                if #available(iOS 15.0, *) {
                    rectangle = (docRequest as? VNDetectDocumentSegmentationRequest)?.results?.first
                }
            }
            
            if rectangle == nil {
                try handler.perform([rectRequest])
                rectangle = rectRequest.results?.first
            }
            
            if let rect = rectangle {
                let corners = [
                    CGPoint(x: rect.topLeft.x, y: 1 - rect.topLeft.y),
                    CGPoint(x: rect.topRight.x, y: 1 - rect.topRight.y),
                    CGPoint(x: rect.bottomRight.x, y: 1 - rect.bottomRight.y),
                    CGPoint(x: rect.bottomLeft.x, y: 1 - rect.bottomLeft.y)
                ]
                onCornersDetected(corners)
            } else {
                onCornersDetected([])
            }
            
            #if DEBUG
            frameCount += 1
            if frameCount % 50 == 0 {
                let elapsed = now.timeIntervalSince(lastDetectionTime)
                print("📷 [VideoHandler] Frame #\(frameCount), detection took \(String(format: "%.1f", elapsed * 1000))ms")
            }
            #endif
        } catch {
            onCornersDetected([])
        }
    }
}

// MARK: - Photo Capture Handler

final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate {
    private let onPhotoCapture: (UIImage) -> Void
    
    init(onPhotoCapture: @escaping (UIImage) -> Void) {
        self.onPhotoCapture = onPhotoCapture
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }
        // Pass the image as-is with its EXIF orientation flag intact.
        // handleStableDocument Step 0 calls normalizeOrientation() which bakes
        // the rotation into pixels exactly once. Normalizing here AND there
        // causes a double-rotation (e.g. .right → .up → rotated again → sideways).
        onPhotoCapture(image)
    }
}

extension UIImage {
    /// Convert UIImage.Orientation to CGImagePropertyOrientation
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:            return .up
        case .down:          return .down
        case .left:          return .left
        case .right:         return .right
        case .upMirrored:    return .upMirrored
        case .downMirrored:  return .downMirrored
        case .leftMirrored:  return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default:    return .up
        }
    }
}

// MARK: - Document Camera UIView

class DocumentCameraUIView: UIView {
    weak var delegate: DocumentCameraDelegate?
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoHandler: VideoSampleBufferHandler?
    private var photoCaptureHandler: PhotoCaptureHandler?
    private var cameraDevice: AVCaptureDevice?
    
    // Pinch-to-zoom tracking
    private var lastZoomFactor: CGFloat = 1.0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupNotifications()
        setupPinchGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNotifications()
        setupPinchGesture()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && captureSession == nil {
            beginCameraSetup()
        }
    }
    
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            stopSession()
        }
    }
    
    override func removeFromSuperview() {
        stopSession()
        NotificationCenter.default.removeObserver(self)
        super.removeFromSuperview()
    }
    
    private func stopSession() {
        guard let session = captureSession else { return }
        captureSession = nil
        // Wrap in @unchecked Sendable to cross thread boundary safely —
        // we nil'd the reference above so only this closure owns it.
        struct SessionBox: @unchecked Sendable { let session: AVCaptureSession }
        let box = SessionBox(session: session)
        DispatchQueue.global(qos: .background).async {
            box.session.stopRunning()
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureRequest),
            name: .triggerDocumentCapture,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTorchRequest(_:)),
            name: .setTorch,
            object: nil
        )
    }

    @objc private func handleCaptureRequest() {
        capturePhoto()
    }

    @objc private func handleTorchRequest(_ notification: Notification) {
        guard let enable = notification.object as? Bool,
              let camera = cameraDevice,
              camera.hasTorch else { return }
        do {
            try camera.lockForConfiguration()
            camera.torchMode = enable ? .on : .off
            if enable {
                try camera.setTorchModeOn(level: 1.0)
            }
            camera.unlockForConfiguration()
        } catch {
            #if DEBUG
            print("⚠️ Torch toggle failed: \(error)")
            #endif
        }
    }
    
    /// Result of background camera configuration — bundles all non-Sendable objects
    /// so they cross the thread boundary exactly once in a single main-thread callback.
    private struct CameraSetupResult: @unchecked Sendable {
        let session: AVCaptureSession
        let photo: AVCapturePhotoOutput
        let video: AVCaptureVideoDataOutput
        let handler: VideoSampleBufferHandler
        let camera: AVCaptureDevice
        let zoom: CGFloat
    }
    
    /// Build and start an AVCaptureSession on a background thread.
    /// Returns nil if the camera is unavailable.
    ///
    /// `nonisolated` because this runs on a background queue (see `beginCameraSetup`)
    /// and touches no main-actor state — it only constructs AVFoundation objects and
    /// returns them bundled in a Sendable `CameraSetupResult`. Without this, the
    /// enclosing `@MainActor` UIView would isolate it to the main actor.
    private nonisolated static func buildCameraSession(
        cornerCallback: @escaping @Sendable ([CGPoint]) -> Void,
        lightCallback:  @escaping @Sendable (Bool) -> Void
    ) -> CameraSetupResult? {
        #if DEBUG
        let t0 = CFAbsoluteTimeGetCurrent()
        #endif
        
        let session = AVCaptureSession()
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            #if DEBUG
            print("📷 [Camera] ❌ No camera device available")
            #endif
            return nil
        }
        
        #if DEBUG
        let t1 = CFAbsoluteTimeGetCurrent()
        print("📷 [Camera] Device acquired: \(String(format: "%.0f", (t1 - t0) * 1000))ms")
        #endif
        
        // Batch all configuration — prevents session from
        // reconfiguring after each add (saves ~200ms)
        session.beginConfiguration()
        
        // Use .high instead of .photo for faster startup.
        // .photo forces the highest-res still pipeline (~200ms extra init).
        // .high gives 1920x1080 video — plenty for preview and detection.
        // We switch to .photo only at capture time.
        session.sessionPreset = .high
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Photo output
        let photo = AVCapturePhotoOutput()
        if session.canAddOutput(photo) {
            session.addOutput(photo)
        }
        
        // Video output for document detection
        let video = AVCaptureVideoDataOutput()
        video.alwaysDiscardsLateVideoFrames = true  // Don't queue stale frames
        let handler = VideoSampleBufferHandler(
            onCornersDetected:   cornerCallback,
            onLightLevelChanged: lightCallback
        )
        video.setSampleBufferDelegate(handler, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))
        if session.canAddOutput(video) {
            session.addOutput(video)
        }

        // CRITICAL: set portrait orientation on the VIDEO connection so that
        // Vision receives portrait-oriented pixel buffers and returns corners
        // in portrait/screen space (not rotated landscape space).
        // Do NOT set orientation on the photo connection — the still photo
        // is delivered in native sensor orientation and normalizeOrientation()
        // in the capture Task handles the rotation. Setting it on the photo
        // output causes a double-rotation (photo arrives pre-rotated, then
        // normalizeOrientation rotates it again → 180° or sideways output).
        if let videoConn = video.connection(with: .video) {
            // 90° = portrait for the back camera (replaces the deprecated
            // .videoOrientation = .portrait API, removed-in-favor-of since iOS 17).
            let portraitAngle: CGFloat = 90
            if videoConn.isVideoRotationAngleSupported(portraitAngle) {
                videoConn.videoRotationAngle = portraitAngle
            }
        }
        
        session.commitConfiguration()
        
        #if DEBUG
        let t2 = CFAbsoluteTimeGetCurrent()
        print("📷 [Camera] Session configured: \(String(format: "%.0f", (t2 - t1) * 1000))ms")
        #endif
        
        // Configure camera hardware after session config
        try? camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        // Start at 1.5x zoom (was 2.0) — less digital processing overhead
        let defaultZoom: CGFloat = min(1.5, camera.activeFormat.videoMaxZoomFactor)
        camera.videoZoomFactor = defaultZoom
        camera.unlockForConfiguration()
        
        #if DEBUG
        let t3 = CFAbsoluteTimeGetCurrent()
        print("📷 [Camera] Hardware configured: \(String(format: "%.0f", (t3 - t2) * 1000))ms")
        #endif
        
        // Start running — this is the single slowest call (~300-500ms, Apple hardware init)
        session.startRunning()
        
        #if DEBUG
        let t4 = CFAbsoluteTimeGetCurrent()
        print("📷 [Camera] startRunning(): \(String(format: "%.0f", (t4 - t3) * 1000))ms")
        print("📷 [Camera] ✅ TOTAL init: \(String(format: "%.0f", (t4 - t0) * 1000))ms")
        #endif
        
        return CameraSetupResult(
            session: session, photo: photo, video: video,
            handler: handler, camera: camera, zoom: defaultZoom
        )
    }
    
    /// Kick off camera configuration on a background thread.
    /// All UIView property writes happen on the main thread callback.
    private func beginCameraSetup() {
        #if DEBUG
        let setupStart = CFAbsoluteTimeGetCurrent()
        #endif
        
        // Capture a weak ref and the delegate callback outside the closure
        let cornerCallback: @Sendable ([CGPoint]) -> Void = { [weak self] corners in
            DispatchQueue.main.async {
                self?.delegate?.didDetectDocument(corners: corners)
            }
        }

        let lightCallback: @Sendable (Bool) -> Void = { [weak self] isLow in
            DispatchQueue.main.async {
                self?.delegate?.didChangeLightLevel(isLow: isLow)
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Static method — no self capture on background thread
            guard let result = Self.buildCameraSession(cornerCallback: cornerCallback,
                                                              lightCallback: lightCallback) else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.window != nil else {
                    result.session.stopRunning()
                    return
                }
                
                // Store references (UIView properties — main thread only)
                self.captureSession = result.session
                self.photoOutput = result.photo
                self.videoOutput = result.video
                self.videoHandler = result.handler
                self.cameraDevice = result.camera
                self.lastZoomFactor = result.zoom
                
                // Create and attach preview layer
                let preview = AVCaptureVideoPreviewLayer(session: result.session)
                preview.videoGravity = .resizeAspectFill
                self.layer.insertSublayer(preview, at: 0)
                self.previewLayer = preview
                
                // Force layout so the preview layer gets the correct frame
                self.setNeedsLayout()
                self.layoutIfNeeded()
                
                // Signal camera ready NOW — don't wait for first document detection.
                // Preview is live as soon as the layer is attached.
                self.delegate?.didDetectDocument(corners: [])
                
                #if DEBUG
                let totalMs = (CFAbsoluteTimeGetCurrent() - setupStart) * 1000
                print("📷 [Camera] ✅ Preview visible: \(String(format: "%.0f", totalMs))ms from beginCameraSetup()")
                #endif
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    // MARK: - Pinch to Zoom
    
    private func setupPinchGesture() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let camera = cameraDevice else { return }
        
        switch gesture.state {
        case .began:
            lastZoomFactor = camera.videoZoomFactor
        case .changed:
            let minZoom: CGFloat = 1.0
            let maxZoom: CGFloat = min(camera.activeFormat.videoMaxZoomFactor, 10.0)
            let desiredZoom = lastZoomFactor * gesture.scale
            let newZoom = max(minZoom, min(maxZoom, desiredZoom))
            
            try? camera.lockForConfiguration()
            camera.videoZoomFactor = newZoom
            camera.unlockForConfiguration()
        case .ended:
            lastZoomFactor = camera.videoZoomFactor
        default:
            break
        }
    }
    
    private func capturePhoto() {
        guard let photoOutput = photoOutput, let session = captureSession else { return }
        
        // Temporarily switch to .photo preset for maximum resolution capture
        // (We use .high for preview to speed up init, but want full quality for the photo)
        if session.sessionPreset != .photo && session.canSetSessionPreset(.photo) {
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.commitConfiguration()
        }
        
        let settings = AVCapturePhotoSettings()
        // Force flash ON when torch is active and the device supports flash.
        // Flash availability lives on AVCaptureDevice, not AVCapturePhotoOutput.
        let isTorchOn    = (cameraDevice?.torchMode == .on)
        let flashSupported = cameraDevice?.isFlashAvailable ?? false
        settings.flashMode = (isTorchOn && flashSupported) ? .on : .auto
        
        photoCaptureHandler = PhotoCaptureHandler { [weak self] image in
            self?.delegate?.didCaptureDocument(image: image)
            
            // Switch back to .high for preview performance
            if let session = self?.captureSession, session.canSetSessionPreset(.high) {
                session.beginConfiguration()
                session.sessionPreset = .high
                session.commitConfiguration()
            }
        }
        
        if let handler = photoCaptureHandler {
            photoOutput.capturePhoto(with: settings, delegate: handler)
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let triggerDocumentCapture = Notification.Name("triggerDocumentCapture")
    static let scanNextPage           = Notification.Name("scanNextPage")
    static let setTorch               = Notification.Name("setTorch")
}

// MARK: - Low-Light Prompt Sheet

struct LowLightPromptSheet: View {
    let onEnableFlash: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "lightbulb.slash.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.yellow)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Poor Lighting Detected")
                    .font(.title3).fontWeight(.bold)
                Text("The scene is too dark for a clear scan. Enable the torch for best results, or move to better lighting before capturing.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                // Enable torch
                Button(action: onEnableFlash) {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("Turn On Torch")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.yellow.opacity(0.18))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }

                // Continue anyway
                Button(action: onDismiss) {
                    Text("Continue Without Torch")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.top, 20)
        .padding(.bottom, 32)
        .background(Color("BrandDeepNavy").ignoresSafeArea())
    }
}

// MARK: - Preview

#Preview {
    SmartDocumentScanner(capturedImage: .constant(nil))
}
