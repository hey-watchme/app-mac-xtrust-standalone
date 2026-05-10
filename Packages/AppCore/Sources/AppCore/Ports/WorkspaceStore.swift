import Foundation

public protocol WorkspaceStore: Sendable {
    func listWorkspaces() throws -> [Workspace]
    func listWorkspaces(organizationID: UUID) throws -> [Workspace]
    func insertWorkspace(_ workspace: Workspace) throws
    func updateWorkspace(_ workspace: Workspace) throws
}
