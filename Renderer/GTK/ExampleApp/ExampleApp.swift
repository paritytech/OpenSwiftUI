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
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 12) {
                    AnimationCard()
                    NavigationLink {
                        AboutView()
                    } label: {
                        Row(title: "About", color: .orange)
                    }
                    ForEach(1..<25, id: \.self) { index in
                        NavigationLink(value: index) {
                            Row(title: "Row \(index)", color: index.isMultiple(of: 2) ? .blue : .purple)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("OpenSwiftUI")
            .navigationDestination(for: Int.self) { index in
                DetailView(index: index, path: $path)
            }
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
                // Keeps the bounce apart from the animated move the circle makes when the
                // capsule above it appears; without it that move replaces the bounce.
                .geometryGroup()

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
    var title: String
    var color: Color

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            Text(title)
            Spacer()
            Text("›")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
        .padding(.horizontal, 16)
    }
}

struct PillLabel: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Capsule().fill(color))
    }
}

struct DetailView: View {
    var index: Int
    @Binding var path: NavigationPath
    @Environment(\.dismiss) private var dismiss
    @State private var count = 0

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(index.isMultiple(of: 2) ? Color.blue : Color.purple)
                .frame(width: 96, height: 96)
            Text("Counted \(count) on this screen")
            PillLabel(title: "Count", color: .yellow)
                .onTapGesture { count += 1 }
            NavigationLink(value: index + 1) {
                PillLabel(title: "Open row \(index + 1)", color: Color.gray.opacity(0.2))
            }
            PillLabel(title: "Go back", color: Color.gray.opacity(0.2))
                .onTapGesture { dismiss() }
            PillLabel(title: "Back to start", color: Color.gray.opacity(0.2))
                .onTapGesture { path = NavigationPath() }
        }
        .navigationTitle("Row \(index)")
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("A SwiftUI app running on Linux")
            Text("Drawn by OpenSwiftUI in a GTK window.")
        }
        .navigationTitle("About")
    }
}
