import Foundation

final class AVLXMLParser: NSObject, XMLParserDelegate {
    private var messages: [AlertMessage] = []
    private var currentValues: [String: String] = [:]
    private var affectedStopIds: [String] = []
    private var affectedRouteIds: [String] = []
    private var currentElement = ""
    private var currentConcernType = ""
    private var currentConcernValue = ""
    private var buffer = ""
    private var insideMessage = false
    private var insideConcern = false

    func parse(data: Data) throws -> [AlertMessage] {
        messages = []
        currentValues = [:]
        affectedStopIds = []
        affectedRouteIds = []
        currentElement = ""
        currentConcernType = ""
        currentConcernValue = ""
        buffer = ""
        insideMessage = false
        insideConcern = false

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? AVLClientError.invalidResponse
        }
        return messages
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        buffer = ""

        if ["message", "alert", "disruption"].contains(currentElement) {
            insideMessage = true
            currentValues = attributeDict.reduce(into: [:]) { result, pair in
                result[pair.key.lowercased()] = pair.value
            }
            affectedStopIds = []
            affectedRouteIds = []
        } else if insideMessage && currentElement == "elementconcerne" {
            insideConcern = true
            currentConcernType = ""
            currentConcernValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = elementName.lowercased()
        defer { buffer = "" }

        guard insideMessage else { return }

        if element == "elementconcerne" {
            appendConcern()
            insideConcern = false
            currentConcernType = ""
            currentConcernValue = ""
            return
        }

        if ["message", "alert", "disruption"].contains(element) {
            messages.append(makeMessage(values: currentValues))
            insideMessage = false
            currentValues = [:]
            affectedStopIds = []
            affectedRouteIds = []
            return
        }

        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            if insideConcern && element == "elementtype" {
                currentConcernType = value
            } else if insideConcern && element == "elementvalue" {
                currentConcernValue = value
            } else {
                currentValues[element] = value
            }
        }
    }

    private func makeMessage(values: [String: String]) -> AlertMessage {
        let title = values["title"] ?? values["titre"] ?? values["titrefr"] ?? values["summary"] ?? "AVL alert"
        let body = values["body"] ?? values["texte"] ?? values["message"] ?? values["description"] ?? values["text"] ?? ""
        let id = values["messageid"] ?? values["id"] ?? "\(title)-\(body)".normalizedForSearch
        let severity = severity(from: values)

        return AlertMessage(
            id: id,
            title: title,
            body: body,
            severity: severity,
            affectedStopIds: unique(affectedStopIds + splitList(values["stop"] ?? values["stopid"] ?? values["stopids"])),
            affectedRouteIds: unique(affectedRouteIds + splitList(values["line"] ?? values["route"] ?? values["routeids"])),
            startsAt: parseAVLDate(values["datedebut"]),
            endsAt: parseAVLDate(values["datefin"]),
            dataSource: .avl
        )
    }

    private func appendConcern() {
        guard !currentConcernValue.isEmpty else { return }
        let normalizedType = currentConcernType.normalizedForSearch
        if normalizedType.contains("ligne") || normalizedType.contains("line") {
            affectedRouteIds.append(currentConcernValue)
        } else if normalizedType.contains("arret") || normalizedType.contains("stop") {
            affectedStopIds.append(currentConcernValue)
        }
    }

    private func severity(from values: [String: String]) -> AlertMessage.Severity {
        if let severity = AlertMessage.Severity(rawValue: values["severity"]?.lowercased() ?? "") {
            return severity
        }

        if values["urgent"]?.lowercased() == "true" {
            return .warning
        }

        let category = (values["categorie"] ?? values["category"] ?? "").normalizedForSearch
        if category.contains("accident") || category.contains("trafic") || category.contains("travaux") {
            return .warning
        }
        if category.contains("info") {
            return .info
        }

        return .unknown
    }

    private func parseAVLDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return Self.dateFormatter.date(from: value)
    }

    private func splitList(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value
            .split { character in character == "," || character == ";" || character == " " }
            .map(String.init)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Luxembourg")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
