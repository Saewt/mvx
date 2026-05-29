import SwiftUI

@MainActor
public struct MvxSectionHeader: View {
    private let title: String
    private let count: Int?
    private let action: (() -> Void)?

    public init(title: String, count: Int? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.count = count
        self.action = action
    }

    public var body: some View {
        let content = HStack(spacing: MvxSpacing.sm) {
            Text(title)
                .textCase(.uppercase)
                .tracking(1.2)
                .font(MvxText.sectionHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let count {
                Text("\(count)")
                    .font(MvxText.meta)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(MvxSurface.cardTint)
                    )
            }
        }
        .padding(.leading, MvxLayout.titleLeadingInset)
        .padding(.trailing, MvxSpacing.md)
        .padding(.vertical, MvxSpacing.xs)

        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}
