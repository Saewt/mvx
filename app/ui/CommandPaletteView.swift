import SwiftUI

@MainActor
public struct CommandPaletteView: View {
    @ObservedObject private var commandHandler: WorkspaceCommandHandler
    @State private var query = ""

    public init(commandHandler: WorkspaceCommandHandler) {
        self.commandHandler = commandHandler
    }

    public var body: some View {
        VStack(spacing: 12) {
            TextField("Search commands", text: $query)
                .textFieldStyle(.roundedBorder)

            List(filteredCommands) { command in
                Button {
                    _ = commandHandler.perform(command.command)
                    commandHandler.dismissCommandPalette()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.title)
                            if !command.keywords.isEmpty {
                                Text(command.keywords.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(!command.isEnabled)
            }
            .listStyle(.inset)

            HStack {
                Spacer()

                Button("Close") {
                    commandHandler.dismissCommandPalette()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }

    private var filteredCommands: [WorkspaceCommandDescriptor] {
        commandHandler.searchCommands(matching: query)
    }
}
