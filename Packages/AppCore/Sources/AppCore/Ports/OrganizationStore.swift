import Foundation

public protocol OrganizationStore: Sendable {
    func listOrganizations() throws -> [Organization]
    func insertOrganization(_ organization: Organization) throws
    func updateOrganization(_ organization: Organization) throws
}
