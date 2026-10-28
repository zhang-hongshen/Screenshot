import ApplicationServices

/// Moving an area that has no scroll bars, such as Chrome's page or a table inside it.
///
/// Chrome offers no scroll position through Accessibility, only `AXScrollToVisible` on every item
/// of the page. Items scrolled out of a box are reported squeezed onto its edge or beyond it, so
/// the next step is to show the first item hidden past the edge; Chrome brings it to the middle,
/// about half a screen. When nothing is hidden that way any more, the area is at its end, so the
/// page around a box is never scrolled by mistake.
extension ScrollArea {
    /// Whether the area is moved by showing hidden items.
    var revealsItems: Bool {
        !canSetPosition && element != nil
    }

    /// Shows the next hidden item past the edge. Returns false when there is none: the end.
    func revealNext(along axis: ScrollAxis, forward: Bool) -> Bool {
        guard let element, let visible = element.frame else { return false }
        let items = items(in: element)
        guard let index = Self.revealTarget(
            itemFrames: items.map(\.frame),
            visible: visible,
            axis: axis,
            forward: forward
        ) else { return false }
        items[index].element.performAction("AXScrollToVisible")
        return true
    }

    /// The first item in reading order, so showing it scrolls to the start.
    func revealStart() {
        guard let element else { return }
        items(in: element).first?.element.performAction("AXScrollToVisible")
    }

    /// The first item fully shown now, to show again when the capture is done.
    func firstVisibleItem() -> AXUIElement? {
        guard let element, let visible = element.frame else { return nil }
        return items(in: element).first { visible.contains($0.frame) && $0.frame.height > 1 }?.element
    }

    /// Picks the item to show next, in reading order: going forward the first one hidden past the
    /// far edge, going back the last one hidden past the near edge. Sideways only items in rows
    /// that are on screen count, so the step does not scroll up or down as well.
    nonisolated static func revealTarget(itemFrames: [CGRect], visible: CGRect, axis: ScrollAxis, forward: Bool) -> Int? {
        let isHidden: (CGRect) -> Bool = { item in
            switch (axis, forward) {
            case (.vertical, true): item.minY >= visible.maxY - 1
            case (.vertical, false): item.maxY <= visible.minY + 1
            case (.horizontal, true):
                item.minX >= visible.maxX - 1 && item.midY > visible.minY && item.midY < visible.maxY
            case (.horizontal, false):
                item.maxX <= visible.minX + 1 && item.midY > visible.minY && item.midY < visible.maxY
            }
        }
        return forward ? itemFrames.firstIndex(where: isHidden) : itemFrames.lastIndex(where: isHidden)
    }

    /// The innermost elements (text, images) inside `element`, in reading order, leaving out the
    /// boxes inside a page, which scroll on their own.
    private func items(in element: AXUIElement) -> [(element: AXUIElement, frame: CGRect)] {
        var items: [(element: AXUIElement, frame: CGRect)] = []
        var visitedCount = 0
        collectItems(in: element, into: &items, visitedCount: &visitedCount)
        return items
    }

    private func collectItems(
        in element: AXUIElement,
        into items: inout [(element: AXUIElement, frame: CGRect)],
        visitedCount: inout Int
    ) {
        visitedCount += 1
        guard visitedCount < 5_000 else { return }
        if innerAreas.contains(where: { $0.element.map { CFEqual($0, element) } ?? false }) { return }
        let children = element.children
        if children.isEmpty {
            if let frame = element.frame, frame.width > 0 || frame.height > 0 {
                items.append((element, frame))
            }
            return
        }
        for child in children {
            collectItems(in: child, into: &items, visitedCount: &visitedCount)
        }
    }
}
