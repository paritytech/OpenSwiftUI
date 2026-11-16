//
//  Screens.swift
//  KitchenSink
//
//  The screens that show one thing each. Those that a script checks are in CheckScreens.swift.

import Foundation
import SwiftUI

// MARK: - Drawing

struct TextScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Large Title").font(.largeTitle)
                Text("Title").font(.title)
                Text("Headline").font(.headline)
                Text("Body")
                Text("Caption").font(.caption).foregroundStyle(Color.gray)
                Text("Bold").bold()
                Text("Italic").italic()
                Text("Underlined").underline()
                Text("Struck through").strikethrough()
                Text("Monospaced 0123").font(.system(.body, design: .monospaced))
                Text("Serif").font(.system(.body, design: .serif))
                Text("Red, blue, green").foregroundStyle(Color.red)
                Text("A longer paragraph wraps onto several lines when it is too wide for the screen, each line measured with the font it is drawn in.")
                Text("Centred text that also wraps onto more than one line when it has to.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
}

struct ShapesScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Rectangle().fill(Color.red).frame(width: 70, height: 70)
                    RoundedRectangle(cornerRadius: 16).fill(Color.green).frame(width: 70, height: 70)
                    Circle().fill(Color.blue).frame(width: 70, height: 70)
                    Capsule().fill(Color.orange).frame(width: 90, height: 40)
                }
                Ellipse().fill(Color.purple).frame(width: 200, height: 80)
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 300, height: 100)
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [.yellow, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 300, height: 60)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The engine cannot outline a path yet (`Path.strokedPath` is not written), and stops the
/// app when asked to.
struct StrokesScreen: View {
    var body: some View {
        HStack(spacing: 16) {
            Circle().stroke(Color.red, lineWidth: 4).frame(width: 70, height: 70)
            RoundedRectangle(cornerRadius: 12).stroke(Color.blue, lineWidth: 2).frame(width: 70, height: 70)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct OpacityScreen: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.red.opacity(0.6)).frame(width: 120, height: 120).offset(x: -40)
                Circle().fill(Color.blue.opacity(0.6)).frame(width: 120, height: 120).offset(x: 40)
            }
            HStack(spacing: 12) {
                ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { value in
                    VStack {
                        Rectangle().fill(Color.green).frame(width: 60, height: 60)
                        Text("\(Int(value * 100))%").font(.caption)
                    }
                    .opacity(value)
                }
            }
            Text("Clipped to its frame, which is narrower than the text")
                .fixedSize()
                .frame(width: 220, alignment: .leading)
                .clipped()
            LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)
                .frame(width: 160, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct TransformsScreen: View {
    var body: some View {
        VStack(spacing: 50) {
            HStack(spacing: 50) {
                square.scaleEffect(0.6)
                square
                square.scaleEffect(1.4)
            }
            HStack(spacing: 50) {
                square.rotationEffect(.degrees(15))
                square.rotationEffect(.degrees(45))
                square.rotationEffect(.degrees(80))
            }
            HStack(spacing: 50) {
                square.offset(y: -15)
                square
                square.offset(y: 15)
            }
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var square: some View {
        RoundedRectangle(cornerRadius: 8).fill(Color.blue).frame(width: 50, height: 50)
    }
}

// MARK: - Layout

struct LayoutScreen: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                box(.red)
                Spacer()
                box(.green)
                Spacer()
                box(.blue)
            }
            HStack(alignment: .top, spacing: 8) {
                box(.orange).frame(height: 30)
                box(.orange).frame(height: 60)
                box(.orange).frame(height: 45)
                Text("top").font(.caption)
            }
            HStack(alignment: .bottom, spacing: 8) {
                box(.purple).frame(height: 30)
                box(.purple).frame(height: 60)
                box(.purple).frame(height: 45)
                Text("bottom").font(.caption)
            }
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 90)
                Text("bottom trailing").padding(8)
            }
            Text("Padded")
                .padding(16)
                .background(Color.yellow)
                .padding(8)
                .background(Color.orange)
            Text("As wide as the screen")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.4))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func box(_ color: Color) -> some View {
        Rectangle().fill(color).frame(width: 50, height: 50)
    }
}

// MARK: - Input

struct ControlsScreen: View {
    @State private var taps = 0
    @State private var presses = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Button pressed \(presses) times")
            Button("A button") { presses += 1 }
            Button {
                presses += 1
            } label: {
                Text("A button with its own label")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.yellow))
            }
            Text("Circle tapped \(taps) times")
            Circle()
                .fill(Color.blue)
                .frame(width: 90, height: 90)
                .onTapGesture { taps += 1 }
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ScrollingScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(0 ..< 12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(checkColours[index % checkColours.count])
                            .frame(width: 120, height: 80)
                            .overlay(Text("Card \(index + 1)"))
                    }
                }
                .padding(16)
            }
            .frame(height: 112)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(0 ..< 40, id: \.self) { index in
                        Text("Row \(index + 1)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

struct NavigationScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Depth 1")
            NavigationLink {
                DeeperScreen(depth: 2)
            } label: {
                Text("Push another screen")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.yellow))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DeeperScreen: View {
    var depth: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Depth \(depth)")
            NavigationLink {
                DeeperScreen(depth: depth + 1)
            } label: {
                Text("Push another screen")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.yellow))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Depth \(depth)")
    }
}

// MARK: - Animation

struct CurvesScreen: View {
    @State private var moved = false

    var body: some View {
        Stage(go: { moved.toggle() }) {
            VStack(alignment: .leading, spacing: 18) {
                row("spring", .spring(response: 0.5, dampingFraction: 0.6), .red)
                row("spring, no bounce", .spring(response: 0.5, dampingFraction: 1), .orange)
                row("ease in and out", .easeInOut(duration: 0.6), .green)
                row("linear", .linear(duration: 0.6), .blue)
                row("ease out, slow", .easeOut(duration: 1.5), .purple)
            }
            .padding(.top, 30)
        }
    }

    private func row(_ title: String, _ animation: Animation, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).padding(.leading, 20)
            Circle()
                .fill(color)
                .frame(width: 44, height: 44)
                .offset(x: moved ? 326 : 20)
                .animation(animation, value: moved)
        }
    }
}

struct ScaleRotationScreen: View {
    @State private var changed = false

    var body: some View {
        Stage(go: { withAnimation(.spring(response: 0.6, dampingFraction: 1)) { changed.toggle() } }) {
            // Scale: a red square that doubles, about its centre at (100, 140).
            Rectangle()
                .fill(Color(red: 0.9, green: 0.1, blue: 0.1))
                .frame(width: 60, height: 60)
                .scaleEffect(changed ? 2 : 1)
                .offset(x: 70, y: 110)
            // Rotation: a blue bar that turns a quarter, about its centre at (280, 140).
            Rectangle()
                .fill(Color(red: 0.1, green: 0.2, blue: 0.9))
                .frame(width: 120, height: 20)
                .rotationEffect(.degrees(changed ? 90 : 0))
                .offset(x: 220, y: 130)
            // Both at once, with a fade.
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green)
                .frame(width: 80, height: 80)
                .rotationEffect(.degrees(changed ? 180 : 0))
                .scaleEffect(changed ? 1.5 : 0.75)
                .opacity(changed ? 1 : 0.4)
                .offset(x: 155, y: 330)
        }
    }
}

struct RepeatingScreen: View {
    @State private var running = false
    @State private var lowered = false

    var body: some View {
        Stage(goTitle: "Move the square down", go: { lowered.toggle() }) {
            // Goes back and forth for ever, between x = 20 and x = 310. "Go" puts it 20
            // lower at once, in the middle of a run, which must not make it lose its place.
            Rectangle()
                .fill(Color(red: 0.9, green: 0.1, blue: 0.1))
                .frame(width: 60, height: 60)
                .offset(x: running ? 310 : 20, y: 100)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: running)
                .offset(y: lowered ? 20 : 0)
            // Fades out and in for ever.
            Circle()
                .fill(Color(red: 0.1, green: 0.2, blue: 0.9))
                .frame(width: 80, height: 80)
                .opacity(running ? 0.15 : 1)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: running)
                .offset(x: 155, y: 220)
            // Turns for ever, always the same way.
            Rectangle()
                .fill(Color.green)
                .frame(width: 120, height: 16)
                .rotationEffect(.degrees(running ? 360 : 0))
                .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: running)
                .offset(x: 135, y: 392)
            // Three times, then it stops at the far end.
            Rectangle()
                .fill(Color.orange)
                .frame(width: 60, height: 60)
                .offset(x: running ? 310 : 20, y: 500)
                .animation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true), value: running)
        }
        .onAppear { running = true }
    }
}

struct TransitionsScreen: View {
    @State private var shown = true

    var body: some View {
        Stage(go: { withAnimation(.easeInOut(duration: 0.5)) { shown.toggle() } }) {
            VStack(spacing: 20) {
                if shown {
                    label("opacity", .red).transition(.opacity)
                    label("move from the leading edge", .green).transition(.move(edge: .leading))
                    label("scale", .blue).transition(.scale)
                    label("scale and opacity", .orange).transition(.scale.combined(with: .opacity))
                }
                label("always here", .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    private func label(_ title: String, _ color: Color) -> some View {
        Text(title)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(color.opacity(0.5)))
    }
}

struct SizesColoursScreen: View {
    @State private var changed = false

    var body: some View {
        Stage(go: { withAnimation(.easeInOut(duration: 0.8)) { changed.toggle() } }) {
            VStack(spacing: 30) {
                RoundedRectangle(cornerRadius: changed ? 40 : 10)
                    .fill(Color.blue)
                    .frame(width: changed ? 300 : 120, height: changed ? 160 : 80)
                Rectangle()
                    .fill(changed ? Color.red : Color.green)
                    .frame(width: 200, height: 80)
                Text("These are sampled in the app: a size is a new layout, a colour a new drawing.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }
}
