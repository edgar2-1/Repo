import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Flattens simple XML (Roku ECP, UPnP device descriptions) into
/// element-name → text, plus a list of repeated child elements with attributes.
///
/// Only the leaf elements under the root are collected; nested structure is
/// not needed for the documents we read.
public final class SimpleXML: NSObject, XMLParserDelegate {
    public struct Element: Equatable, Sendable {
        public var name: String
        public var attributes: [String: String]
        public var text: String
    }

    public private(set) var values: [String: String] = [:]
    public private(set) var elements: [Element] = []

    private var current: Element?
    private var depth = 0

    public static func parse(_ data: Data) -> SimpleXML? {
        let xml = SimpleXML()
        let parser = XMLParser(data: data)
        parser.delegate = xml
        parser.shouldProcessNamespaces = false
        return parser.parse() ? xml : nil
    }

    public subscript(_ name: String) -> String? { values[name] }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        depth += 1
        current = Element(name: elementName, attributes: attributeDict, text: "")
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        current?.text += string
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        depth -= 1
        if var element = current, element.name == elementName {
            element.text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep the last value for repeated names; collect every leaf in order.
            values[elementName] = element.text
            elements.append(element)
        }
        current = nil
    }
}
