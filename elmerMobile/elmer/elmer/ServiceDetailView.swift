import SwiftUI

struct ServiceDetailView: View {
    let service: RemoteService
    
    var body: some View {
        VStack {
            // With CloudKit relay, we always connect through the relay
            Group {
                // Check service type first, then API format
                if service.baseService.type == .imageGeneration || service.baseService.apiFormat == .comfyui {
                    ComfyUIView(service: service)
                } else {
                    switch service.baseService.apiFormat {
                    case .openai, .custom:
                        ChatView(service: service)
                    case .comfyui:
                        ComfyUIView(service: service)
                    case .gradio:
                        // For Gradio, we might need a different approach with relay
                        Text("Gradio interfaces not yet supported via CloudKit relay")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}