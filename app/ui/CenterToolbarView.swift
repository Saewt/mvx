import SwiftUI

@MainActor
public struct CenterToolbarView: View {
    @ObservedObject var workspace: SessionWorkspace
    @ObservedObject var commandHandler: WorkspaceCommandHandler

    public init(workspace: SessionWorkspace, commandHandler: WorkspaceCommandHandler) {
        self.workspace = workspace
        self.commandHandler = commandHandler
    }

    public var body: some View {
        let descriptor = workspace.activeDescriptor

        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.88, green: 0.56, blue: 0.36))

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor?.displayTitle ?? "No Active Session")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Text(descriptor?.workingDirectoryPath?.split(separator: "/").last.map(String.init) ?? "No context")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(commandHandler.paneCommands(), id: \.command) { cmd in
                    Button {
                        _ = commandHandler.perform(cmd.command)
                    } label: {
                        Image(systemName: cmd.command.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(cmd.isEnabled ? 0.08 : 0.03))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!cmd.isEnabled)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.10, green: 0.10, blue: 0.09))
    }
}
