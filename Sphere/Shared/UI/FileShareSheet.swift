import SwiftUI
import UIKit

struct FileShareSheet: UIViewControllerRepresentable {
    var fileURL: URL

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
        // Share content is immutable for each presentation.
    }
}
