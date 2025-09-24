import SwiftUI
import CoreImage

struct ExportView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Connect iPhone")
                .font(.title2)
                .bold()
            
            if let qrData = serviceManager.generateQRPayload(),
               let qrImage = generateQRCode(from: qrData) {
                
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                
                Text("Scan this QR code with the iPhone app to connect via CloudKit relay")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
            } else {
                Text("Unable to generate connection QR code")
                    .foregroundColor(.secondary)
            }
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 400, height: 500)
    }
    
    func generateQRCode(from data: Data) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else { return nil }
        
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}