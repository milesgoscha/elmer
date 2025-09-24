//
//  MultimodalMessageView.swift
//  elmer
//
//  Displays chat messages that can contain both text and images
//

import SwiftUI
import Photos

// MARK: - Multimodal Message View
struct MultimodalMessageView: View {
    let message: ChatMessage
    @State private var loadedImage: UIImage?
    @State private var isLoadingImage = false
    
    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                    // Display text content if present (selective markdown formatting)
                    if !message.content.isEmpty {
                        Text(formatSelectiveMarkdown(message.content))
                            .font(.system(size: 15))
                            .foregroundColor(message.isUser ? .white : ElmeriOSTheme.textColor)
                            .padding(.horizontal, message.isUser ? 16 : 0)
                            .padding(.vertical, message.isUser ? 12 : 0)
                            .background(
                                Group {
                                    if message.isUser {
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                                    }
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    }
                    
                    // Display image if present
                    if message.hasImage {
                        ImageDisplayView(message: message, loadedImage: $loadedImage, isLoadingImage: $isLoadingImage)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Simple text formatting (preserves model's original formatting)
    private func formatSelectiveMarkdown(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = UIFont.systemFont(ofSize: 15)
        result.foregroundColor = message.isUser ? UIColor.white : UIColor(ElmeriOSTheme.textColor)
        return result
    }
    
    // MARK: - Enhanced Markdown Support (kept for reference)
    private func formatMarkdown(_ text: String) -> AttributedString {
        do {
            // Configure markdown options for full formatting support
            var options = AttributedString.MarkdownParsingOptions()
            options.allowsExtendedAttributes = true
            options.interpretedSyntax = .full  // Enable full markdown including code blocks
            
            // Try to parse as markdown with full formatting
            var attributedString = try AttributedString(markdown: text, options: options)
            
            // Apply base styling while preserving markdown formatting
            let range = attributedString.startIndex..<attributedString.endIndex
            attributedString[range].font = .system(size: 15)
            attributedString[range].foregroundColor = message.isUser ? .white : ElmeriOSTheme.textColor
            
            // Enhanced styling for code blocks and inline code
            enhanceCodeFormatting(&attributedString)
            
            return attributedString
        } catch {
            // Fallback: try with manual code block formatting
            return formatTextWithCodeBlocks(text)
        }
    }
    
    private func enhanceCodeFormatting(_ attributedString: inout AttributedString) {
        // For now, let's use a simpler approach - the markdown parser should handle most formatting
        // We'll apply monospace font to any text that looks like code
        let fullRange = attributedString.startIndex..<attributedString.endIndex
        
        // Apply consistent font styling - the markdown parser will handle the actual formatting
        attributedString[fullRange].font = .system(size: 15)
        attributedString[fullRange].foregroundColor = message.isUser ? .white : ElmeriOSTheme.textColor
    }
    
    private func formatTextWithCodeBlocks(_ text: String) -> AttributedString {
        // Simplified fallback - just return plain text with basic formatting
        var result = AttributedString(text)
        result.font = .system(size: 15)
        result.foregroundColor = message.isUser ? .white : ElmeriOSTheme.textColor
        return result
    }
}

// MARK: - Image Display View
struct ImageDisplayView: View {
    let message: ChatMessage
    @Binding var loadedImage: UIImage?
    @Binding var isLoadingImage: Bool
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
                    .contextMenu {
                        Button {
                            saveImageToPhotos(image)
                        } label: {
                            Label("Save to Photos", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            shareImage(image)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
            } else if isLoadingImage {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .frame(width: 200, height: 150)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .frame(width: 200, height: 150)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                            Text("Image failed to load")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    )
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .alert("Save Image", isPresented: $showingSaveAlert) {
            Button("OK") { }
        } message: {
            Text(saveAlertMessage)
        }
    }

    private func saveImageToPhotos(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .limited:
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    saveAlertMessage = "Image saved to Photos"
                    showingSaveAlert = true
                case .denied, .restricted:
                    saveAlertMessage = "Photo library access denied. Please enable in Settings."
                    showingSaveAlert = true
                case .notDetermined:
                    saveAlertMessage = "Please grant photo library access to save images."
                    showingSaveAlert = true
                @unknown default:
                    saveAlertMessage = "Unable to save image"
                    showingSaveAlert = true
                }
            }
        }
    }

    private func shareImage(_ image: UIImage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            return
        }

        let activityController = UIActivityViewController(activityItems: [image], applicationActivities: nil)

        // For iPad
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = rootViewController.view
            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        rootViewController.present(activityController, animated: true)
    }
    
    private func loadImageIfNeeded() {
        guard loadedImage == nil && !isLoadingImage else { return }
        
        print("📷 Loading image for message \(message.id): hasImage=\(message.hasImage), imageData=\(message.imageData?.count ?? 0) bytes, assetURL=\(message.imageAssetURL ?? "none")")
        
        // Try to load from direct image data first
        if let imageData = message.imageData {
            loadedImage = UIImage(data: imageData)
            print("✅ Loaded image from direct data: \(loadedImage != nil)")
            return
        }
        
        // If no direct data, try loading from CKAsset URL
        if let assetURLString = message.imageAssetURL,
           let assetURL = URL(string: assetURLString) {
            isLoadingImage = true
            
            Task {
                do {
                    let data: Data
                    
                    if assetURL.isFileURL {
                        // Load from local file (CloudKit asset cache)
                        data = try Data(contentsOf: assetURL)
                        print("✅ Loaded image from local file: \(assetURL.lastPathComponent)")
                    } else {
                        // Load from network URL
                        let (networkData, _) = try await URLSession.shared.data(from: assetURL)
                        data = networkData
                        print("✅ Loaded image from network: \(assetURL)")
                    }
                    
                    await MainActor.run {
                        loadedImage = UIImage(data: data)
                        isLoadingImage = false
                    }
                } catch {
                    print("❌ Failed to load image from asset URL \(assetURL): \(error)")
                    await MainActor.run {
                        isLoadingImage = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        // Text-only message
        MultimodalMessageView(
            message: ChatMessage(role: .user, content: "Hello, can you generate an image of a cat?")
        )
        
        // Text + Image message (mock)
        MultimodalMessageView(
            message: ChatMessage(
                role: .assistant,
                content: "Here's a beautiful cat image I generated for you:",
                imageData: Data(), // Mock data
                imageMetadata: ImageMetadata(width: 512, height: 512, format: "PNG", sizeBytes: 1024)
            )
        )
        
        // Image-only message
        MultimodalMessageView(
            message: ChatMessage(
                role: .assistant,
                content: "",
                imageData: Data(), // Mock data
                imageMetadata: ImageMetadata(width: 1024, height: 1024, format: "JPEG", sizeBytes: 2048)
            )
        )
    }
    .background(Color.black)
}