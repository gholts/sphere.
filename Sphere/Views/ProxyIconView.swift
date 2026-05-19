import SwiftUI

struct ProxyIconView: View {
    var icon: String?
    var size: CGFloat = 16
    
    var body: some View {
        if let icon, !icon.isEmpty {
            ProxyIconBody(icon: icon)
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: 3))
                .accessibilityHidden(true)
        }
    }
}

private struct ProxyIconBody: View {
    var icon: String
    
    var body: some View {
        if icon.hasPrefix("data:image/svg+xml") {
            Image(systemName: "network")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            CachedProxyIconImage(icon: icon)
                .id(icon)
        }
    }
}

private struct CachedProxyIconImage: View {
    var icon: String
    @State private var image: CGImage?
    
    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Color.clear
                .task(id: icon) {
                    image = await ProxyIconCache.shared.image(for: icon)
                }
        }
    }
}
