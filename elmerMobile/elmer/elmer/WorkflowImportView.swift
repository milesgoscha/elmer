import SwiftUI

struct WorkflowImportView: View {
    let onImport: ([String: Any]) -> Void
    @Binding var isPresented: Bool
    @State private var workflowText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import ComfyUI Workflow")
                        .font(.headline)
                    
                    Text("1. In ComfyUI, design your workflow")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("2. Click 'Export' → 'API Format'")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("3. Copy the JSON and paste it below:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                
                TextEditor(text: $workflowText)
                    .font(.system(.caption, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if workflowText.isEmpty {
                                VStack {
                                    HStack {
                                        Text("Paste your ComfyUI workflow JSON here...")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .allowsHitTesting(false)
                            }
                        }
                    )
                    .padding(.horizontal)
                
                HStack(spacing: 16) {
                    Button("Clear") {
                        workflowText = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(workflowText.isEmpty)
                    
                    Spacer()
                    
                    Button("Import Workflow") {
                        importWorkflow()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(workflowText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("Import Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    func importWorkflow() {
        guard let data = workflowText.data(using: .utf8) else {
            errorMessage = "Invalid text format"
            showingError = true
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Validate that it looks like a ComfyUI workflow
                var hasValidNodes = false
                for (_, value) in json {
                    if let node = value as? [String: Any],
                       node["class_type"] != nil {
                        hasValidNodes = true
                        break
                    }
                }
                
                if hasValidNodes {
                    onImport(json)
                    isPresented = false
                } else {
                    errorMessage = "This doesn't appear to be a valid ComfyUI workflow. Make sure to export in 'API Format'."
                    showingError = true
                }
            } else {
                errorMessage = "Invalid JSON format"
                showingError = true
            }
        } catch {
            errorMessage = "Failed to parse JSON: \(error.localizedDescription)"
            showingError = true
        }
    }
}