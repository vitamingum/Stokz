import SwiftUI

/// UserRowView displays a user in a list with their rank and net worth
/// LIQUID DEATH STYLE - Bold Black & White
struct UserRowView: View {
    let user: User
    let rank: Int?
    let netWorth: Double?
    let profitLossPercent: Double?
    var showRank: Bool = true
    var onTap: (() -> Void)?
    
    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                // Rank Badge
                if showRank, let rank = rank {
                    ZStack {
                        Circle()
                            .fill(rankColor(rank))
                            .frame(width: 32, height: 32)
                        
                        if rank <= 3 {
                            Text("💀")
                                .font(.system(size: 14))
                        } else {
                            Text("\(rank)")
                                .font(.system(size: 12, weight: .black))
                                .foregroundColor(.black)
                        }
                    }
                }
                
                // User Avatar
                UserAvatarView(user: user, size: 40)
                
                // User Name
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.displayName.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1)
                        .foregroundColor(.white)
                    
                    if let profitLossPercent = profitLossPercent {
                        HStack(spacing: 4) {
                            Image(systemName: profitLossPercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(abs(profitLossPercent), specifier: "%.2f")%")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(profitLossPercent >= 0 ? .white : Color(white: 0.4))
                    }
                }
                
                Spacer()
                
                // Net Worth
                if let netWorth = netWorth {
                    Text(netWorth.asCurrency)
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(.white)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return .white
        case 2: return Color(white: 0.6)
        case 3: return Color(white: 0.4)
        default: return Color(white: 0.25)
        }
    }
}

/// Simple user avatar view (Liquid Death Style)
struct UserAvatarView: View {
    let user: User
    var size: CGFloat = 40
    
    var body: some View {
        if let photoURL = user.photoURL, let url = URL(string: photoURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                initialsView
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.2))
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .black))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var initials: String {
        let components = user.displayName.split(separator: " ")
        let first = components.first?.prefix(1) ?? ""
        let last = components.count > 1 ? components.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)".uppercased()
    }
}

/// Compact user row for inline lists (Liquid Death Style)
struct CompactUserRowView: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 8) {
            UserAvatarView(user: user, size: 24)
            
            Text(user.displayName.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack {
        UserRowView(
            user: User(
                id: "1",
                email: "alice@example.com",
                displayName: "Alice Johnson",
                photoURL: nil,
                createdAt: Date()
            ),
            rank: 1,
            netWorth: 125_430.50,
            profitLossPercent: 25.43
        )
        
        Divider()
        
        UserRowView(
            user: User(
                id: "2",
                email: "bob@example.com",
                displayName: "Bob Smith",
                photoURL: nil,
                createdAt: Date()
            ),
            rank: 2,
            netWorth: 98_750.25,
            profitLossPercent: -1.25
        )
    }
    .padding()
}
