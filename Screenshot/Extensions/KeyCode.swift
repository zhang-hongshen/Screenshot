/// Hardware key codes for the keys the capture overlays react to. AppKit reports keys by these numbers.
enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    /// Space, Page Up, Page Down, Home, End and the arrow keys.
    static let scrolling: Set<UInt16> = [49, 116, 121, 115, 119, 123, 124, 125, 126]
}
