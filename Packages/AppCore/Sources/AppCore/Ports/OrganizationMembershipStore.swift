import Foundation

public protocol OrganizationMembershipStore: Sendable {
    func listOrganizationMemberships() throws -> [OrganizationMembership]
    func listOrganizationMemberships(organizationID: UUID) throws -> [OrganizationMembership]
    func listOrganizationMemberships(accountID: UUID) throws -> [OrganizationMembership]
    func insertOrganizationMembership(_ membership: OrganizationMembership) throws
    func updateOrganizationMembership(_ membership: OrganizationMembership) throws
}
