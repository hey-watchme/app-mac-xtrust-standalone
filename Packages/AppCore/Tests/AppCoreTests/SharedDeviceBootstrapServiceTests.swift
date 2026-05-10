import Foundation
import Testing
@testable import AppCore

struct SharedDeviceBootstrapServiceTests {
    @Test
    func createsDefaultSharedDeviceContextWhenStoresAreEmpty() throws {
        let store = SharedDeviceBootstrapInMemoryStore()
        let clock = SharedDeviceBootstrapFixedClock(now: Date(timeIntervalSince1970: 1_700_300_000))
        let service = SharedDeviceBootstrapService(
            organizationStore: store,
            workspaceStore: store,
            deviceStore: store,
            accountStore: store,
            organizationMembershipStore: store,
            clock: clock
        )

        let context = try service.run(
            configuration: .developmentDefault(deviceName: "Conference Mac")
        )

        #expect(context.organization.name == "XTrust Local Organization")
        #expect(context.workspace.organizationID == context.organization.id)
        #expect(context.device.workspaceID == context.workspace.id)
        #expect(context.bootstrapMembership.organizationID == context.organization.id)
        #expect(context.bootstrapMembership.accountID == context.bootstrapAccount.id)
        #expect(try store.listOrganizations().count == 1)
        #expect(try store.listWorkspaces().count == 1)
        #expect(try store.listDevices().count == 1)
        #expect(try store.listAccounts().count == 1)
        #expect(try store.listOrganizationMemberships().count == 1)
    }

    @Test
    func reusesExistingSharedDeviceContextOnSecondRun() throws {
        let store = SharedDeviceBootstrapInMemoryStore()
        let clock = SharedDeviceBootstrapFixedClock(now: Date(timeIntervalSince1970: 1_700_300_500))
        let service = SharedDeviceBootstrapService(
            organizationStore: store,
            workspaceStore: store,
            deviceStore: store,
            accountStore: store,
            organizationMembershipStore: store,
            clock: clock
        )

        let first = try service.run(configuration: .developmentDefault(deviceName: "Conference Mac"))
        let second = try service.run(
            configuration: SharedDeviceBootstrapConfiguration(
                organizationName: "Different Org",
                workspaceName: "Different Workspace",
                workspaceCode: "DIFF",
                deviceDisplayName: "Different Device",
                deviceLocationLabel: "Different Room",
                bootstrapAccountDisplayName: "Different Operator"
            )
        )

        #expect(second == first)
        #expect(try store.listOrganizations().count == 1)
        #expect(try store.listWorkspaces().count == 1)
        #expect(try store.listDevices().count == 1)
        #expect(try store.listAccounts().count == 1)
        #expect(try store.listOrganizationMemberships().count == 1)
    }
}

private final class SharedDeviceBootstrapInMemoryStore:
    OrganizationStore,
    WorkspaceStore,
    DeviceStore,
    AccountStore,
    OrganizationMembershipStore,
    @unchecked Sendable
{
    private var organizations: [Organization] = []
    private var workspaces: [Workspace] = []
    private var devices: [Device] = []
    private var accounts: [Account] = []
    private var memberships: [OrganizationMembership] = []

    func listOrganizations() throws -> [Organization] {
        organizations.sorted { $0.createdAt < $1.createdAt }
    }

    func insertOrganization(_ organization: Organization) throws {
        organizations.append(organization)
    }

    func updateOrganization(_ organization: Organization) throws {
        guard let index = organizations.firstIndex(where: { $0.id == organization.id }) else { return }
        organizations[index] = organization
    }

    func listWorkspaces() throws -> [Workspace] {
        workspaces.sorted { $0.createdAt < $1.createdAt }
    }

    func listWorkspaces(organizationID: UUID) throws -> [Workspace] {
        workspaces
            .filter { $0.organizationID == organizationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func insertWorkspace(_ workspace: Workspace) throws {
        workspaces.append(workspace)
    }

    func updateWorkspace(_ workspace: Workspace) throws {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        workspaces[index] = workspace
    }

    func listDevices() throws -> [Device] {
        devices.sorted { $0.createdAt < $1.createdAt }
    }

    func listDevices(workspaceID: UUID) throws -> [Device] {
        devices
            .filter { $0.workspaceID == workspaceID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func insertDevice(_ device: Device) throws {
        devices.append(device)
    }

    func updateDevice(_ device: Device) throws {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index] = device
    }

    func listAccounts() throws -> [Account] {
        accounts.sorted { $0.createdAt < $1.createdAt }
    }

    func insertAccount(_ account: Account) throws {
        accounts.append(account)
    }

    func updateAccount(_ account: Account) throws {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
    }

    func listOrganizationMemberships() throws -> [OrganizationMembership] {
        memberships.sorted { $0.createdAt < $1.createdAt }
    }

    func listOrganizationMemberships(organizationID: UUID) throws -> [OrganizationMembership] {
        memberships
            .filter { $0.organizationID == organizationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func listOrganizationMemberships(accountID: UUID) throws -> [OrganizationMembership] {
        memberships
            .filter { $0.accountID == accountID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func insertOrganizationMembership(_ membership: OrganizationMembership) throws {
        memberships.append(membership)
    }

    func updateOrganizationMembership(_ membership: OrganizationMembership) throws {
        guard let index = memberships.firstIndex(where: { $0.id == membership.id }) else { return }
        memberships[index] = membership
    }
}

private struct SharedDeviceBootstrapFixedClock: Clock {
    let currentDate: Date

    init(now: Date) {
        self.currentDate = now
    }

    func now() -> Date {
        currentDate
    }
}
