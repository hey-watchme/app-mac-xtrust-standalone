import Foundation

public struct SharedDeviceContext: Equatable, Sendable {
    public let organization: Organization
    public let workspace: Workspace
    public let device: Device
    public let bootstrapAccount: Account
    public let bootstrapMembership: OrganizationMembership

    public init(
        organization: Organization,
        workspace: Workspace,
        device: Device,
        bootstrapAccount: Account,
        bootstrapMembership: OrganizationMembership
    ) {
        self.organization = organization
        self.workspace = workspace
        self.device = device
        self.bootstrapAccount = bootstrapAccount
        self.bootstrapMembership = bootstrapMembership
    }
}

public struct SharedDeviceBootstrapConfiguration: Equatable, Sendable {
    public let organizationName: String
    public let workspaceName: String
    public let workspaceCode: String?
    public let deviceDisplayName: String
    public let deviceLocationLabel: String?
    public let bootstrapAccountDisplayName: String
    public let bootstrapAccountEmployeeCode: String?

    public init(
        organizationName: String,
        workspaceName: String,
        workspaceCode: String? = nil,
        deviceDisplayName: String,
        deviceLocationLabel: String? = nil,
        bootstrapAccountDisplayName: String,
        bootstrapAccountEmployeeCode: String? = nil
    ) {
        self.organizationName = organizationName
        self.workspaceName = workspaceName
        self.workspaceCode = workspaceCode
        self.deviceDisplayName = deviceDisplayName
        self.deviceLocationLabel = deviceLocationLabel
        self.bootstrapAccountDisplayName = bootstrapAccountDisplayName
        self.bootstrapAccountEmployeeCode = bootstrapAccountEmployeeCode
    }

    public static func developmentDefault(deviceName: String) -> SharedDeviceBootstrapConfiguration {
        SharedDeviceBootstrapConfiguration(
            organizationName: "XTrust Local Organization",
            workspaceName: "Default Workspace",
            workspaceCode: "DEFAULT",
            deviceDisplayName: deviceName,
            deviceLocationLabel: "This Mac",
            bootstrapAccountDisplayName: "Local Operator",
            bootstrapAccountEmployeeCode: nil
        )
    }
}

public struct SharedDeviceBootstrapService: Sendable {
    private let organizationStore: any OrganizationStore
    private let workspaceStore: any WorkspaceStore
    private let deviceStore: any DeviceStore
    private let accountStore: any AccountStore
    private let organizationMembershipStore: any OrganizationMembershipStore
    private let clock: any Clock

    public init(
        organizationStore: any OrganizationStore,
        workspaceStore: any WorkspaceStore,
        deviceStore: any DeviceStore,
        accountStore: any AccountStore,
        organizationMembershipStore: any OrganizationMembershipStore,
        clock: any Clock
    ) {
        self.organizationStore = organizationStore
        self.workspaceStore = workspaceStore
        self.deviceStore = deviceStore
        self.accountStore = accountStore
        self.organizationMembershipStore = organizationMembershipStore
        self.clock = clock
    }

    public func run(configuration: SharedDeviceBootstrapConfiguration) throws -> SharedDeviceContext {
        let organization = try ensureOrganization(configuration: configuration)
        let workspace = try ensureWorkspace(organizationID: organization.id, configuration: configuration)
        let device = try ensureDevice(
            organizationID: organization.id,
            workspaceID: workspace.id,
            configuration: configuration
        )
        let account = try ensureBootstrapAccount(configuration: configuration)
        let membership = try ensureMembership(organizationID: organization.id, accountID: account.id)

        return SharedDeviceContext(
            organization: organization,
            workspace: workspace,
            device: device,
            bootstrapAccount: account,
            bootstrapMembership: membership
        )
    }

    private func ensureOrganization(
        configuration: SharedDeviceBootstrapConfiguration
    ) throws -> Organization {
        if let existing = try organizationStore.listOrganizations().first {
            return existing
        }

        let organization = Organization(
            name: configuration.organizationName,
            createdAt: clock.now()
        )
        try organizationStore.insertOrganization(organization)
        return organization
    }

    private func ensureWorkspace(
        organizationID: UUID,
        configuration: SharedDeviceBootstrapConfiguration
    ) throws -> Workspace {
        if let existing = try workspaceStore.listWorkspaces(organizationID: organizationID).first {
            return existing
        }

        let workspace = Workspace(
            organizationID: organizationID,
            name: configuration.workspaceName,
            code: configuration.workspaceCode,
            createdAt: clock.now()
        )
        try workspaceStore.insertWorkspace(workspace)
        return workspace
    }

    private func ensureDevice(
        organizationID: UUID,
        workspaceID: UUID,
        configuration: SharedDeviceBootstrapConfiguration
    ) throws -> Device {
        if let existing = try deviceStore.listDevices(workspaceID: workspaceID).first {
            return existing
        }

        let device = Device(
            organizationID: organizationID,
            workspaceID: workspaceID,
            displayName: configuration.deviceDisplayName,
            locationLabel: configuration.deviceLocationLabel,
            createdAt: clock.now()
        )
        try deviceStore.insertDevice(device)
        return device
    }

    private func ensureBootstrapAccount(
        configuration: SharedDeviceBootstrapConfiguration
    ) throws -> Account {
        if let existing = try accountStore.listAccounts().first {
            return existing
        }

        let account = Account(
            displayName: configuration.bootstrapAccountDisplayName,
            employeeCode: configuration.bootstrapAccountEmployeeCode,
            createdAt: clock.now()
        )
        try accountStore.insertAccount(account)
        return account
    }

    private func ensureMembership(
        organizationID: UUID,
        accountID: UUID
    ) throws -> OrganizationMembership {
        if let existing = try organizationMembershipStore
            .listOrganizationMemberships(organizationID: organizationID)
            .first(where: { $0.accountID == accountID }) {
            return existing
        }

        let membership = OrganizationMembership(
            organizationID: organizationID,
            accountID: accountID,
            role: .admin,
            createdAt: clock.now()
        )
        try organizationMembershipStore.insertOrganizationMembership(membership)
        return membership
    }
}
