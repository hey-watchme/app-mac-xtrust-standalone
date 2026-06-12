import SwiftUI

// MARK: - Workspace Rail (60px left column)
// Static decorative rail with XTRUST logo tile + placeholder workspace tiles.

struct WorkspaceRail: View {
    let onShowSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Logo tile
            logoTile
                .padding(.top, 12)

            Divider()
                .background(XT.C.navDivider)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            // Workspace tiles
            VStack(spacing: 6) {
                workspaceTile(initial: "渋", gradient: workspaceGradient1, isActive: true)
                workspaceTile(initial: "M",  gradient: workspaceGradient2, isActive: false)
                workspaceTile(initial: "大", gradient: workspaceGradient3, isActive: false)
                workspaceTile(initial: "SG", gradient: workspaceGradient4, isActive: false)
            }
            .padding(.horizontal, 10)

            // Add workspace (dashed)
            addWorkspaceButton
                .padding(.top, 6)
                .padding(.horizontal, 10)

            Spacer()

            // Bottom icons
            VStack(spacing: 6) {
                railIconButton(systemName: "headphones")
                railIconButton(systemName: "gearshape", action: onShowSettings)
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 10)
        }
        .frame(width: XT.Layout.railWidth)
        .background(XT.C.navRail)
    }

    // MARK: - Logo Tile

    private var logoTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#6366F1"), Color(hex: "#4F46E5")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 38, height: 38)
            Text("X")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
    }

    // MARK: - Workspace Tiles

    private func workspaceTile(
        initial: String,
        gradient: LinearGradient,
        isActive: Bool
    ) -> some View {
        HStack(spacing: 0) {
            // Active indicator bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.white)
                .frame(width: isActive ? 3 : 0, height: 24)
                .padding(.leading, isActive ? 0 : 3)
                .animation(.easeInOut(duration: 0.15), value: isActive)

            Spacer(minLength: isActive ? 4 : 7)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(gradient)
                    .frame(width: 34, height: 34)
                    .opacity(isActive ? 1.0 : 0.7)
                Text(initial)
                    .font(.system(size: initial.count > 1 ? 11 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            Spacer()
        }
        .frame(height: 38)
    }

    private var workspaceGradient1: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#3B82F6"), Color(hex: "#2563EB")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var workspaceGradient2: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#14B8A6"), Color(hex: "#0D9488")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var workspaceGradient3: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#F59E0B"), Color(hex: "#D97706")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var workspaceGradient4: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#A855F7"), Color(hex: "#7C3AED")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // MARK: - Add Workspace

    private var addWorkspaceButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(XT.C.navDivider, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 38, height: 38)
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(XT.C.navTextMute)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rail Icon Button

    private func railIconButton(systemName: String, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(XT.C.navTextDim)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
