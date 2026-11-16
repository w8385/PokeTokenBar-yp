import Foundation

/// A TM is bought once per move and then works for every Pokémon of yours that learns the move by machine.
/// The inventory key is `tm:<moveID>` with a count of 1; it is never consumed.
enum MachineMove {
    static let keyPrefix = "tm:"

    static func inventoryKey(_ moveID: Int) -> String { keyPrefix + String(moveID) }

    static func ownedIDs(in inventory: [String: Int]) -> Set<Int> {
        Set(inventory.compactMap { key, count in
            guard count > 0, key.hasPrefix(keyPrefix) else { return nil }
            return Int(key.dropFirst(keyPrefix.count))
        })
    }
}
