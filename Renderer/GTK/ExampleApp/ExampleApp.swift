import Foundation
import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear(perform: blockMainThreadIfAsked)
        }
    }
}

/// For seeing what still moves when the app is busy: with EXAMPLE_STALL_AT and
/// EXAMPLE_STALL_FOR set (milliseconds), the main thread is blocked for that long, that long
/// after launch.
private func blockMainThreadIfAsked() {
    let environment = ProcessInfo.processInfo.environment
    guard let at = environment["EXAMPLE_STALL_AT"].flatMap(Double.init),
          let duration = environment["EXAMPLE_STALL_FOR"].flatMap(Double.init) else {
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + at / 1000) {
        let monotonic = ProcessInfo.processInfo.systemUptime
        FileHandle.standardError.write(Data("ExampleApp: main thread blocked at \(monotonic)\n".utf8))
        Thread.sleep(forTimeInterval: duration / 1000)
        FileHandle.standardError.write(Data("ExampleApp: main thread free again\n".utf8))
    }
}

struct ContentView: View {
    @State private var path = NavigationPath()
    @State private var favourites: Set<Int> = []
    @State private var showsSettings = false

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
                    NavigationLink {
                        TypographyView()
                    } label: {
                        Row(title: "Typography", color: .green)
                    }
                    ForEach(1..<25, id: \.self) { index in
                        NavigationLink(value: index) {
                            Row(
                                title: favourites.contains(index) ? "Row \(index) ★" : "Row \(index)",
                                color: index.isMultiple(of: 2) ? .blue : .purple
                            )
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("OpenSwiftUI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") { showsSettings = true }
                }
            }
            .navigationDestination(for: Int.self) { index in
                // `isFavourite` is a plain value: the stack rebuilds the screen when it changes.
                DetailView(index: index, isFavourite: favourites.contains(index), path: $path) {
                    favourites.formSymmetricDifference([index])
                }
            }
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView()
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
    var isFavourite: Bool
    @Binding var path: NavigationPath
    var toggleFavourite: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var count = 0

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(index.isMultiple(of: 2) ? Color.blue : Color.purple)
                .frame(width: 96, height: 96)
            Text(isFavourite ? "A favourite" : "Not a favourite")
                .foregroundStyle(.secondary)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isFavourite ? "★" : "☆") { toggleFavourite() }
                    .font(.title2)
            }
        }
    }
}

struct SettingsView: View {
    @State private var colour: String?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(["Red", "Green", "Blue"], id: \.self) { name in
                Row(title: name, color: ColourView.color(named: name))
                    .onTapGesture { colour = name }
            }
        }
        .navigationTitle("Settings")
        .navigationDestination(item: $colour) { name in
            ColourView(name: name)
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Text("Three colours")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ColourView: View {
    var name: String

    static func color(named name: String) -> Color {
        switch name {
        case "Red": .red
        case "Green": .green
        default: .blue
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Self.color(named: name))
            .padding(24)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
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

struct TypographyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Large Title").font(.largeTitle)
                Text("Title").font(.title)
                Text("Title 2").font(.title2)
                Text("Headline").font(.headline)
                Text("Body")
                Text("Subheadline").font(.subheadline).foregroundStyle(.secondary)
                Text("Caption").font(.caption).foregroundStyle(.secondary)
                Text("Bold, ").bold() + Text("italic, ").italic() + Text("red.").foregroundColor(.red)
                Text("Serif design").font(.system(size: 20, design: .serif))
                Text("Rounded heavy").font(.system(size: 20, weight: .heavy, design: .rounded))
                Text("Monospaced 0123").font(.system(.body, design: .monospaced))
                Text("Underline").underline()
                Text("Strikethrough").strikethrough()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Colour from the container")
                    Text("and its font").fontWeight(.light)
                }
                .font(.title3)
                .foregroundStyle(.blue)
                Text("A longer paragraph wraps onto several lines, each measured with the same font it is drawn in.")
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("Typography")
    }
}
