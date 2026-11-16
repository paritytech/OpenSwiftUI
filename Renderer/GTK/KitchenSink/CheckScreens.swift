//
//  CheckScreens.swift
//  KitchenSink
//
//  Screens that check-layers.sh runs and measures. What it measures depends on the numbers
//  here: where things start, how far they go, and their colours. Change them together with
//  support/layer-checks.py.

import Foundation
import SwiftUI

/// Colours a script can tell apart. Rows of a list cycle through them.
let checkColours: [Color] = [
    Color(red: 0.9, green: 0.1, blue: 0.1),
    Color(red: 0.1, green: 0.7, blue: 0.1),
    Color(red: 0.1, green: 0.2, blue: 0.9),
    Color(red: 0.9, green: 0.6, blue: 0.0),
    Color(red: 0.6, green: 0.1, blue: 0.8),
    Color(red: 0.0, green: 0.7, blue: 0.8),
]

/// A red square that, half a second after "Go", takes half a second to go from x = 20 to
/// x = 310, at y = 100.
struct DelayedMoveScreen: View {
    @State private var moved = false

    var body: some View {
        Stage(go: { moved.toggle() }) {
            Rectangle()
                .fill(checkColours[0])
                .frame(width: 60, height: 60)
                .offset(x: moved ? 310 : 20, y: 100)
                .animation(.easeInOut(duration: 0.5).delay(0.5), value: moved)
        }
    }
}

/// A blue square inside a container that is an effect, not a group. On "Go" the container
/// goes down by 30 and the square goes right by 250 inside it, both with one spring. The
/// container has less far to go and comes to rest first. The square starts at (20, 100).
struct MovingContainerScreen: View {
    @State private var moved = false

    var body: some View {
        Stage(go: { withAnimation(.spring(response: 0.6, dampingFraction: 1)) { moved.toggle() } }) {
            ZStack(alignment: .topLeading) {
                Color.clear
                Rectangle()
                    .fill(checkColours[2])
                    .frame(width: 60, height: 60)
                    .offset(x: moved ? 250 : 0)
            }
            .frame(width: 350, height: 100)
            .opacity(0.9)
            .offset(x: 20, y: moved ? 130 : 100)
        }
    }
}

/// A list of coloured rows, 80 points high, under a strip that takes the colour of the row
/// last tapped. "Go" empties the list and fills it again a moment later.
struct EmptiedScrollScreen: View {
    @State private var rows = Array(0 ..< 30)
    @State private var tapped: Int?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(tapped.map { checkColours[$0 % checkColours.count] } ?? Color.white)
                .frame(height: 60)
                .overlay(Text(tapped.map { "Row \($0 + 1)" } ?? "Tap a row"))
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        Rectangle()
                            .fill(checkColours[row % checkColours.count])
                            .frame(height: 80)
                            .overlay(Text("Row \(row + 1)"))
                            .onTapGesture { tapped = row }
                    }
                }
            }
            GoBar(title: "Empty the list and fill it again") {
                rows = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    rows = Array(0 ..< 30)
                }
            }
        }
    }
}
