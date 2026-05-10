import Foundation
import Testing
@testable import AppCore

struct SharedDeviceSchemaTests {
    @Test
    func initializesAndPersistsRootEntities() throws {
        let store = SQLiteSessionStore(databaseURL: makeDatabaseURL())
        try store.initialize()

        let createdAt = Date(timeIntervalSince1970: 1_700_100_000)
        let organization = Organization(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            name: "Acme Corp",
            createdAt: createdAt
        )
        let workspace = Workspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            organizationID: organization.id,
            name: "Tokyo Branch",
            code: "TYO",
            createdAt: createdAt.addingTimeInterval(1)
        )
        let device = Device(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            organizationID: organization.id,
            workspaceID: workspace.id,
            displayName: "Room A Device",
            locationLabel: "Room A",
            createdAt: createdAt.addingTimeInterval(2)
        )
        let account = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            displayName: "Kaya",
            employeeCode: "E-104",
            createdAt: createdAt.addingTimeInterval(3)
        )
        let membership = OrganizationMembership(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            organizationID: organization.id,
            accountID: account.id,
            role: .admin,
            createdAt: createdAt.addingTimeInterval(4)
        )

        try store.insertOrganization(organization)
        try store.insertWorkspace(workspace)
        try store.insertDevice(device)
        try store.insertAccount(account)
        try store.insertOrganizationMembership(membership)

        #expect(try store.listOrganizations() == [organization])
        #expect(try store.listWorkspaces() == [workspace])
        #expect(try store.listWorkspaces(organizationID: organization.id) == [workspace])
        #expect(try store.listDevices() == [device])
        #expect(try store.listDevices(workspaceID: workspace.id) == [device])
        #expect(try store.listAccounts() == [account])
        #expect(try store.listOrganizationMemberships() == [membership])
        #expect(try store.listOrganizationMemberships(organizationID: organization.id) == [membership])
        #expect(try store.listOrganizationMemberships(accountID: account.id) == [membership])
    }

    @Test
    func updatesRootEntities() throws {
        let store = SQLiteSessionStore(databaseURL: makeDatabaseURL())
        try store.initialize()

        let createdAt = Date(timeIntervalSince1970: 1_700_200_000)
        let organization = Organization(name: "Acme", createdAt: createdAt)
        let workspace = Workspace(
            organizationID: organization.id,
            name: "Osaka",
            createdAt: createdAt.addingTimeInterval(1)
        )
        let device = Device(
            organizationID: organization.id,
            workspaceID: workspace.id,
            displayName: "Device 1",
            createdAt: createdAt.addingTimeInterval(2)
        )
        let account = Account(
            displayName: "Operator",
            createdAt: createdAt.addingTimeInterval(3)
        )
        let membership = OrganizationMembership(
            organizationID: organization.id,
            accountID: account.id,
            createdAt: createdAt.addingTimeInterval(4)
        )

        try store.insertOrganization(organization)
        try store.insertWorkspace(workspace)
        try store.insertDevice(device)
        try store.insertAccount(account)
        try store.insertOrganizationMembership(membership)

        let updatedOrganization = Organization(
            id: organization.id,
            name: "Acme Updated",
            status: .inactive,
            createdAt: organization.createdAt
        )
        let updatedWorkspace = Workspace(
            id: workspace.id,
            organizationID: workspace.organizationID,
            name: "Osaka West",
            code: "OSW",
            status: .inactive,
            createdAt: workspace.createdAt
        )
        let updatedDevice = Device(
            id: device.id,
            organizationID: device.organizationID,
            workspaceID: device.workspaceID,
            displayName: "Device 1B",
            locationLabel: "West Room",
            status: .inactive,
            createdAt: device.createdAt
        )
        let updatedAccount = Account(
            id: account.id,
            displayName: "Operator B",
            employeeCode: "EMP-42",
            status: .inactive,
            createdAt: account.createdAt
        )
        let updatedMembership = OrganizationMembership(
            id: membership.id,
            organizationID: membership.organizationID,
            accountID: membership.accountID,
            role: .admin,
            status: .inactive,
            createdAt: membership.createdAt
        )

        try store.updateOrganization(updatedOrganization)
        try store.updateWorkspace(updatedWorkspace)
        try store.updateDevice(updatedDevice)
        try store.updateAccount(updatedAccount)
        try store.updateOrganizationMembership(updatedMembership)

        #expect(try store.listOrganizations() == [updatedOrganization])
        #expect(try store.listWorkspaces() == [updatedWorkspace])
        #expect(try store.listDevices() == [updatedDevice])
        #expect(try store.listAccounts() == [updatedAccount])
        #expect(try store.listOrganizationMemberships() == [updatedMembership])
    }

    @Test
    func insertsAndUpdatesAccessSessions() throws {
        let store = SQLiteSessionStore(databaseURL: makeDatabaseURL())
        try store.initialize()

        let createdAt = Date(timeIntervalSince1970: 1_700_210_000)
        let organization = Organization(name: "Org", createdAt: createdAt)
        let workspace = Workspace(
            organizationID: organization.id,
            name: "Workspace",
            createdAt: createdAt.addingTimeInterval(1)
        )
        let device = Device(
            organizationID: organization.id,
            workspaceID: workspace.id,
            displayName: "Device",
            createdAt: createdAt.addingTimeInterval(2)
        )
        let account = Account(
            displayName: "Operator",
            createdAt: createdAt.addingTimeInterval(3)
        )
        let accessSession = AccessSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000210")!,
            deviceID: device.id,
            accountID: account.id,
            startedAt: createdAt.addingTimeInterval(4),
            authenticationMethod: .localMock
        )

        try store.insertOrganization(organization)
        try store.insertWorkspace(workspace)
        try store.insertDevice(device)
        try store.insertAccount(account)
        try store.insertAccessSession(accessSession)

        #expect(try store.listAccessSessions() == [accessSession])
        #expect(try store.listAccessSessions(deviceID: device.id) == [accessSession])

        let updated = accessSession.ended(
            at: createdAt.addingTimeInterval(10),
            status: .loggedOut
        )
        try store.updateAccessSession(updated)

        #expect(try store.listAccessSessions(deviceID: device.id) == [updated])
    }
}

private func makeDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        .appendingPathExtension("sqlite")
}
