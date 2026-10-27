import Foundation
import ScreenCaptureKit

/// The web page shown in a Safari or Chrome window, read and scrolled with JavaScript sent as an
/// Apple Event.
///
/// Accessibility does not show which boxes inside a page scroll (Safari leaves them out of its
/// tree, Chrome gives no scroll position), but the page itself knows: every element whose
/// `overflow` scrolls and whose content is larger than its box. Their `scrollTop` and `scrollLeft`
/// can be set exactly, so no scroll-wheel events are needed. This only works after the user turned
/// on "Allow JavaScript from Apple Events" in the browser's developer settings.
@MainActor
final class WebPage {
    /// One scrolling box of the page, in CSS pixels.
    struct Area: Decodable {
        /// The visible box without borders and scroll bars, relative to the top-left of the viewport.
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let scrollLeft: Double
        let scrollTop: Double
        let maximumLeft: Double
        let maximumTop: Double
        /// The nearest scrolling area around this one, -1 for the page itself.
        let parent: Int

        var rect: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }

        var scrollOffset: CGPoint {
            CGPoint(x: scrollLeft, y: scrollTop)
        }
    }

    /// Every scrolling area of the page; the first one is the page itself.
    struct Layout: Decodable {
        let viewportWidth: Double
        let areas: [Area]
    }

    private enum Browser {
        case safari
        case chrome
    }

    private static let browsers: [String: Browser] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chrome,
        "com.microsoft.edgemac": .chrome,
        "com.brave.Browser": .chrome,
    ]

    private let bundleIdentifier: String
    private let browser: Browser
    private let windowID: Int

    /// Returns nil when the window does not belong to a supported browser or cannot be found in its scripting windows.
    init?(window: SCWindow) {
        guard let bundleIdentifier = window.owningApplication?.bundleIdentifier,
              let browser = Self.browsers[bundleIdentifier] else { return nil }
        self.bundleIdentifier = bundleIdentifier
        self.browser = browser

        // The scripting window with the same bounds is the captured window.
        let source = "tell application id \"\(bundleIdentifier)\" to get {id, bounds} of every window"
        guard let result = try? Self.run(source),
              let ids = result.atIndex(1), let bounds = result.atIndex(2),
              ids.numberOfItems == bounds.numberOfItems, ids.numberOfItems > 0 else { return nil }
        let frame = window.frame
        var matchingID: Int?
        for index in 1...ids.numberOfItems {
            guard let box = bounds.atIndex(index), box.numberOfItems == 4,
                  let left = box.atIndex(1)?.int32Value, let top = box.atIndex(2)?.int32Value,
                  let right = box.atIndex(3)?.int32Value, let bottom = box.atIndex(4)?.int32Value else { continue }
            let scriptFrame = CGRect(x: Int(left), y: Int(top), width: Int(right - left), height: Int(bottom - top))
            if abs(scriptFrame.minX - frame.minX) < 2, abs(scriptFrame.minY - frame.minY) < 2,
               abs(scriptFrame.width - frame.width) < 2, abs(scriptFrame.height - frame.height) < 2 {
                matchingID = ids.atIndex(index).map { Int($0.int32Value) }
                break
            }
        }
        guard let matchingID else { return nil }
        windowID = matchingID
    }

    /// Finds every scrolling area. Throws when the browser does not allow JavaScript from Apple Events.
    func layout() throws -> Layout {
        let json = try runJavaScript(Self.helpers + """
            var root = document.scrollingElement || document.documentElement;
            var list = [root];
            var elements = document.querySelectorAll('*');
            for (var i = 0; i < elements.length; i++) {
                var element = elements[i];
                var canScrollDown = element.scrollHeight - element.clientHeight >= 4;
                var canScrollRight = element.scrollWidth - element.clientWidth >= 4;
                if (!canScrollDown && !canScrollRight) continue;
                if (element.clientWidth < 40 || element.clientHeight < 40) continue;
                var style = getComputedStyle(element);
                var scrolls = /auto|scroll|overlay/;
                if ((canScrollDown && scrolls.test(style.overflowY)) || (canScrollRight && scrolls.test(style.overflowX))) {
                    list.push(element);
                }
            }
            window.__screenshotScrollAreas = list;
            return JSON.stringify({ viewportWidth: innerWidth, areas: list.map(describe) });
            """)
        return try JSONDecoder().decode(Layout.self, from: Data(json.utf8))
    }

    /// Scrolls area `index` of the last `layout()` and returns where it is now.
    @discardableResult
    func scroll(area index: Int, to offset: CGPoint) throws -> Area {
        let json = try runJavaScript(Self.helpers + """
            var element = window.__screenshotScrollAreas[\(index)];
            element.scrollTo({ left: \(offset.x), top: \(offset.y), behavior: 'instant' });
            return JSON.stringify(describe(element));
            """)
        return try JSONDecoder().decode(Area.self, from: Data(json.utf8))
    }

    func area(_ index: Int) throws -> Area {
        let json = try runJavaScript(Self.helpers + """
            return JSON.stringify(describe(window.__screenshotScrollAreas[\(index)]));
            """)
        return try JSONDecoder().decode(Area.self, from: Data(json.utf8))
    }

    // MARK: - Running scripts

    /// `describe` turns an element of `window.__screenshotScrollAreas` into an `Area`.
    private static let helpers = """
        function describe(element) {
            var list = window.__screenshotScrollAreas;
            var root = list[0];
            var box = element === root
                ? { x: 0, y: 0 }
                : { x: element.getBoundingClientRect().left + element.clientLeft,
                    y: element.getBoundingClientRect().top + element.clientTop };
            var parent = -1;
            for (var ancestor = element.parentElement; ancestor && element !== root; ancestor = ancestor.parentElement) {
                parent = list.indexOf(ancestor);
                if (parent >= 0) break;
            }
            if (element !== root && parent < 0) parent = 0;
            return {
                x: box.x, y: box.y, width: element.clientWidth, height: element.clientHeight,
                scrollLeft: element.scrollLeft, scrollTop: element.scrollTop,
                maximumLeft: Math.max(0, element.scrollWidth - element.clientWidth),
                maximumTop: Math.max(0, element.scrollHeight - element.clientHeight),
                parent: parent
            };
        }

        """

    private func runJavaScript(_ body: String) throws -> String {
        let javaScript = "(function () {\n\(body)\n})()"
        let literal = javaScript
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = switch browser {
        case .safari:
            "tell application id \"\(bundleIdentifier)\" to do JavaScript \"\(literal)\" in current tab of window id \(windowID)"
        case .chrome:
            "tell application id \"\(bundleIdentifier)\" to execute active tab of window id \(windowID) javascript \"\(literal)\""
        }
        guard let result = try Self.run(source).stringValue else { throw WebPageError.noResult }
        return result
    }

    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw WebPageError.scriptFailed("") }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw WebPageError.scriptFailed(errorInfo[NSAppleScript.errorMessage] as? String ?? "")
        }
        return result
    }
}

private enum WebPageError: LocalizedError {
    case scriptFailed(String)
    case noResult

    var errorDescription: String? {
        switch self {
        case .scriptFailed(let message): "The browser did not run the script. \(message)"
        case .noResult: "The browser returned nothing."
        }
    }
}
