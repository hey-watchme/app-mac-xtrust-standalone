import Foundation

public protocol AccountStore: Sendable {
    func listAccounts() throws -> [Account]
    func insertAccount(_ account: Account) throws
    func updateAccount(_ account: Account) throws
}
