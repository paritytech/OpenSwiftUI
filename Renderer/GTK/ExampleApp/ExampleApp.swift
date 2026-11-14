import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                AnimationCard()
                ForEach(1..<25, id: \.self) { index in
                    Row(index: index)
                }
            }
            .padding(.vertical, 16)
        }
    }
}

struct AnimationCard: View {
    @State private var expanded = false
    @State private var taps = 0
    @State private var bouncing = false

    var body: some View {
        VStack(spacing: 20) {
            Text("OpenSwiftUI on Linux")
            Text("Taps: \(taps)")

            RoundedRectangle(cornerRadius: expanded ? 44 : 16)
                .fill(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: expanded ? 300 : 150, height: expanded ? 220 : 110)
                .rotationEffect(.degrees(expanded ? 8 : 0))
                .frame(height: 260)

            if expanded {
                Capsule()
                    .fill(Color.green)
                    .frame(width: 220, height: 36)
                    .transition(.scale.combined(with: .opacity))
            }

            Circle()
                .fill(Color.orange)
                .frame(width: 48, height: 48)
                .offset(x: bouncing ? 120 : -120)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: bouncing)

            Text("Tap to animate")
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.yellow))
                .onTapGesture {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        expanded.toggle()
                        taps += 1
                    }
                }
        }
        .onAppear { bouncing = true }
    }
}

struct Row: View {
    var index: Int

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(index.isMultiple(of: 2) ? Color.blue : Color.purple)
                .frame(width: 28, height: 28)
            Text("Row \(index)")
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
        .padding(.horizontal, 16)
    }
}
