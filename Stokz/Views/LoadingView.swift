import SwiftUI

/// LoadingView - Branded loading screen with app icon
struct LoadingView: View {
    var message: String = "Loading..."
    @State private var isAnimating = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Pure black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // App Icon with pulse animation
                ZStack {
                    // Outer glow pulse
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)
                    
                    // App Icon
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        )
                }
                
                // Brand name
                Text("STOKZ")
                    .font(.system(size: 42, weight: .black))
                    .tracking(8)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Loading indicator
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text(message.uppercased())
                        .font(.system(size: 12, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(Color(white: 0.5))
                }
                
                Spacer()
                    .frame(height: 80)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
}

#Preview {
    LoadingView(message: "Loading portfolio...")
}
