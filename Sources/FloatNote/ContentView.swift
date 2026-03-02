import SwiftUI
import AppKit

struct ContentView: View {

    @EnvironmentObject private var model: NoteModel
    @State private var showSettings = false
    @State private var isHoveringHandle = false

    var body: some View {
        ZStack(alignment: .top) {
            // ── Frosted glass background ──────────────────────────────────
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Drag handle strip ─────────────────────────────────────
                DragHandle(isHovering: $isHoveringHandle)
                    .frame(height: 18) // taller hit target, visually 6pt

                // ── Text editor ───────────────────────────────────────────
                TextEditor(text: $model.text)
                    .font(.system(size: 13, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .contextMenu {
                        Button("Settings…") { showSettings = true }
                        Divider()
                        Button("Clear Note") { model.text = "" }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Drag Handle

struct DragHandle: View {

    @Binding var isHovering: Bool

    var body: some View {
        ZStack {
            // Slightly darker tint over the material so the handle is visible.
            Rectangle()
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0.06))
                .frame(height: 18)

            // Visual pill indicator.
            Capsule()
                .fill(Color.primary.opacity(isHovering ? 0.45 : 0.25))
                .frame(width: 28, height: 4)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .hoverCursor(.openHand)
        // The window is `isMovableByWindowBackground = true`, so dragging
        // from any part of the view moves it. The handle strip gives visual
        // affordance; no extra drag gesture needed.
    }
}

// MARK: - Cursor modifier

struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside { cursor.push() } else { NSCursor.pop() }
            }
    }
}

extension View {
    func hoverCursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}
