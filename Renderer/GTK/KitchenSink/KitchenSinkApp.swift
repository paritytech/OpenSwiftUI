//
//  KitchenSinkApp.swift
//  KitchenSink
//
//  One screen for each thing the Linux hosts are meant to show, to look at and to check.
//  Launched as it is, the app lists the screens. With KITCHEN_SINK_SCREEN set to a screen's
//  id it shows that screen alone, filling the window, so that a script knows where things are
//  (check-layers.sh).
//
//  KITCHEN_SINK_STALL=<after>,<for> (milliseconds) blocks the main thread for a while after
//  every tap on a screen's bar at the bottom, to see what still moves when the app is busy.

import Foundation
import SwiftUI

@main
struct KitchenSinkApp: App {
    var body: some Scene {
        WindowGroup {
            if let id = ProcessInfo.processInfo.environment["KITCHEN_SINK_SCREEN"] {
                if let screen = Screen.all.first(where: { $0.id == id }) {
                    screen.content.background(Color.white)
                } else {
                    Text("No screen called \(id). There are: \(Screen.all.map(\.id).joined(separator: ", "))")
                        .padding(20)
                }
            } else {
                Catalogue()
            }
        }
    }
}

struct Screen: Identifiable {
    var id: String
    var title: String
    var section: String
    var content: AnyView

    init<Content: View>(_ id: String, _ title: String, in section: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.section = section
        self.content = AnyView(content())
    }

    static let all: [Screen] = [
        Screen("text", "Text", in: "Drawing") { TextScreen() },
        Screen("shapes", "Shapes and fills", in: "Drawing") { ShapesScreen() },
        Screen("opacity", "Opacity and clipping", in: "Drawing") { OpacityScreen() },
        Screen("transforms", "Scale, rotation, offset", in: "Drawing") { TransformsScreen() },
        Screen("layout", "Stacks and frames", in: "Layout") { LayoutScreen() },
        Screen("controls", "Buttons and taps", in: "Input") { ControlsScreen() },
        Screen("scrolling", "Scrolling, both ways", in: "Input") { ScrollingScreen() },
        Screen("emptied-scroll", "A scroll view that empties", in: "Input") { EmptiedScrollScreen() },
        Screen("navigation", "Pushing screens", in: "Input") { NavigationScreen() },
        Screen("curves", "Springs and curves", in: "Animation") { CurvesScreen() },
        Screen("delayed-move", "A move after a delay", in: "Animation") { DelayedMoveScreen() },
        Screen("moving-container", "A move inside a move", in: "Animation") { MovingContainerScreen() },
        Screen("scale-rotation", "Scale and rotation, animated", in: "Animation") { ScaleRotationScreen() },
        Screen("repeating", "Animations that repeat", in: "Animation") { RepeatingScreen() },
        Screen("transitions", "Transitions", in: "Animation") { TransitionsScreen() },
        Screen("sizes-colours", "Sizes and colours, animated", in: "Animation") { SizesColoursScreen() },
        Screen("strokes", "Outlined shapes (stops the app)", in: "Not working yet") { StrokesScreen() },
    ]
}

struct Catalogue: View {
    private var sections: [String] {
        var seen: [String] = []
        for screen in Screen.all where !seen.contains(screen.section) {
            seen.append(screen.section)
        }
        return seen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sections, id: \.self) { section in
                        Text(section)
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        ForEach(Screen.all.filter { $0.section == section }) { screen in
                            NavigationLink {
                                screen.content
                                    .navigationTitle(screen.title)
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                HStack {
                                    Text(screen.title)
                                    Spacer()
                                    Text("›")
                                }
                                .padding(.horizontal, 20)
                                .frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Kitchen sink")
        }
    }
}

/// What a screen does when it is told to go: a bar across the bottom of the screen, always in
/// the same place, 80 points high.
struct GoBar: View {
    var title = "Go"
    var action: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
            .frame(height: 80)
            .overlay(Text(title).font(.headline))
            .onTapGesture {
                action()
                blockMainThreadIfAsked()
            }
    }
}

/// A screen's content above its bar. What is inside is placed from the top left corner.
struct Stage<Content: View>: View {
    var goTitle = "Go"
    var go: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GoBar(title: goTitle, action: go)
        }
    }
}

private func blockMainThreadIfAsked() {
    guard let setting = ProcessInfo.processInfo.environment["KITCHEN_SINK_STALL"] else {
        return
    }
    let parts = setting.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else {
        return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + parts[0] / 1000) {
        say("main thread blocked")
        Thread.sleep(forTimeInterval: parts[1] / 1000)
        say("main thread free again")
    }
}

/// On the clock the compositor's records use.
private func say(_ what: String) {
    let time = ProcessInfo.processInfo.systemUptime
    FileHandle.standardError.write(Data("KitchenSink: [\(time)] \(what)\n".utf8))
}
