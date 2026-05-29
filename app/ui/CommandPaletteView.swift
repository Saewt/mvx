import SwiftUI

@MainActor
public struct CommandPaletteView: View {
    @ObservedObject private var commandHandler: WorkspaceCommandHandler
    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool

    public init(commandHandler: WorkspaceCommandHandler) {
        self.commandHandler = commandHandler
    }

    public var body: some View {
        let commands = filteredCommands

        VStack(spacing: 0) {
            HStack(spacing: MvxSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search commands", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.primary)
                    .focused($isSearchFieldFocused)
            }
            .padding(.horizontal, MvxSpacing.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                    .fill(MvxSurface.base)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MvxRadius.control, style: .continuous)
                    .stroke(MvxSurface.hairline, lineWidth: 1)
            )
            .padding(MvxSpacing.lg)

            Divider()
                .opacity(0.5)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(commands) { command in
                        Button {
                            _ = commandHandler.perform(command.command)
                            commandHandler.dismissCommandPalette()
                        } label: {
                            HStack(spacing: MvxSpacing.sm) {
                                Image(systemName: command.command.symbolName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(command.isEnabled ? .secondary : .tertiary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(command.title)
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                        .foregroundStyle(command.isEnabled ? .primary : .tertiary)

                                    if !command.keywords.isEmpty {
                                        Text(command.keywords.joined(separator: ", "))
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, MvxSpacing.md)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!command.isEnabled)
                    }
                }
                .padding(.horizontal, MvxSpacing.sm)
                .padding(.vertical, MvxSpacing.xs)
            }

            Divider()
                .opacity(0.5)

            HStack {
                Button {
                    guard let first = commands.first(where: \.isEnabled) else { return }
                    _ = commandHandler.perform(first.command)
                    commandHandler.dismissCommandPalette()
                } label: {
                    HStack(spacing: MvxSpacing.xs) {
                        Text("↩").font(.system(.caption, design: .rounded))
                        Text("Run First").font(.system(.caption, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return)
                .disabled(commands.filter(\.isEnabled).isEmpty)

                Spacer()

                Button {
                    commandHandler.dismissCommandPalette()
                } label: {
                    HStack(spacing: MvxSpacing.xs) {
                        Text("Esc").font(.system(.caption, design: .rounded))
                        Text("Close").font(.system(.caption, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, MvxSpacing.lg)
            .padding(.vertical, 8)
        }
        .frame(width: 420, height: 320)
        .background(
            RoundedRectangle(cornerRadius: MvxRadius.container, style: .continuous)
                .fill(MvxSurface.overlay)
        )
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    private var filteredCommands: [WorkspaceCommandDescriptor] {
        commandHandler.searchCommands(matching: query)
    }
}
