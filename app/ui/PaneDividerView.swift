import SwiftUI

@MainActor
public struct PaneDividerView: View {
    public let axis: WorkspaceSplitAxis
    public let isActiveFocusLine: Bool
    public let onDrag: (CGFloat) -> Void

    @State private var isHovered = false
    @State private var isDragging = false

    public init(
        axis: WorkspaceSplitAxis,
        isActiveFocusLine: Bool = false,
        onDrag: @escaping (CGFloat) -> Void
    ) {
        self.axis = axis
        self.isActiveFocusLine = isActiveFocusLine
        self.onDrag = onDrag
    }

    public var body: some View {
        let isVerticalSeam = axis == .vertical

        Rectangle()
            .fill(dividerColor)
            .frame(
                width: isVerticalSeam ? 6 : nil,
                height: isVerticalSeam ? nil : 6
            )
            .contentShape(Rectangle())
            .shadow(color: dividerGlowColor, radius: isDragging ? 8 : (isActiveFocusLine ? 5 : 0))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    hoverCursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true

                        let delta = isVerticalSeam
                            ? value.translation.width
                            : value.translation.height
                        onDrag(delta)
                    }
                      .onEnded { _ in
                          isDragging = false
                      }
              )
            .animation(.easeInOut(duration: 0.14), value: isHovered)
            .animation(.easeInOut(duration: 0.12), value: isDragging)
            .animation(.easeInOut(duration: 0.22), value: isActiveFocusLine)
    }

    private var dividerColor: Color {
        if isDragging {
            return Color.accentColor.opacity(0.9)
        }

        if isActiveFocusLine {
            return isHovered
                ? Color.accentColor.opacity(0.84)
                : Color.accentColor.opacity(0.64)
        }

        if isHovered {
            return Color.white.opacity(0.22)
        }

        return Color.white.opacity(0.08)
    }

    private var dividerGlowColor: Color {
        if isDragging {
            return Color.accentColor.opacity(0.42)
        }

        if isActiveFocusLine {
            return Color.accentColor.opacity(0.24)
        }

        return .clear
    }

    private var hoverCursor: NSCursor {
        axis == .vertical ? .resizeLeftRight : .resizeUpDown
    }
}
