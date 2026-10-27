import ApplicationServices

/// Small typed readers for the Accessibility attributes that automatic scrolling needs.
extension AXUIElement {
    var role: String? {
        value(of: kAXRoleAttribute) as? String
    }

    var children: [AXUIElement] {
        value(of: kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    var parent: AXUIElement? {
        element(of: kAXParentAttribute)
    }

    var windows: [AXUIElement] {
        value(of: kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    /// Frame in global screen coordinates with a top-left origin, the same space ScreenCaptureKit uses.
    var frame: CGRect? {
        guard let positionValue = value(of: kAXPositionAttribute),
              let sizeValue = value(of: kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        // AXValue is a CoreFoundation type, so the casts always succeed once the attribute exists.
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    func element(of attribute: String) -> AXUIElement? {
        guard let value = value(of: attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func number(of attribute: String) -> Double? {
        (value(of: attribute) as? NSNumber)?.doubleValue
    }

    @discardableResult
    func setNumber(_ number: Double, for attribute: String) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, NSNumber(value: number)) == .success
    }

    private func value(of attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
