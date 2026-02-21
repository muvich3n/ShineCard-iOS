//
//  ContentView.swift
//  ShineCard
//

import SwiftUI

struct ContentView: View {
    @State private var touchLocation: CGPoint = .zero
    @State private var isTouching: Bool = false
    
    var body: some View {
        ZStack {
            // 深色背景
            Color(hex: "#1a1a2e")
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Text("✨ Shine Card")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                // Metal 渲染的卡片
                ShineCardView(
                    touchLocation: $touchLocation,
                    isTouching: $isTouching
                )
                .frame(width: 300, height: 420)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
                
                Text("触摸卡片查看光泽效果")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// 颜色扩展
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
