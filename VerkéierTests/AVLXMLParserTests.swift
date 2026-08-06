import Foundation
import Testing

@testable import Verkeier

struct AVLXMLParserTests {
    @Test func parsesSimpleAlertXML() throws {
        let xml = """
            <alerts>
              <message id="m1">
                <title>Line F1 diverted</title>
                <description>Stop Hill Lift is not served.</description>
                <severity>warning</severity>
                <line>16</line>
              </message>
            </alerts>
            """

        let messages = try AVLXMLParser().parse(data: Data(xml.utf8))

        #expect(messages.count == 1)
        #expect(messages[0].id == "m1")
        #expect(messages[0].title == "Line F1 diverted")
        #expect(messages[0].body == "Stop Hill Lift is not served.")
        #expect(messages[0].severity == .warning)
        #expect(messages[0].affectedRouteIds == ["16"])
    }

    @Test func parsesVDLMessageSchema() throws {
        let xml = """
            <Messages>
              <Message>
                <MessageID>5147</MessageID>
                <DateDebut>2026-01-12 07:00</DateDebut>
                <DateFin>2026-07-17 17:00</DateFin>
                <Urgent>true</Urgent>
                <Categorie>Travaux</Categorie>
                <Titre>Rue Charles Martel mise en sens unique</Titre>
                <Texte>Les lignes 12 et 15 sont deviees.</Texte>
                <ElementsConcernes>
                  <ElementConcerne>
                    <ElementType>Ligne</ElementType>
                    <ElementValue>12</ElementValue>
                  </ElementConcerne>
                  <ElementConcerne>
                    <ElementType>Ligne</ElementType>
                    <ElementValue>15</ElementValue>
                  </ElementConcerne>
                  <ElementConcerne>
                    <ElementType>Arret</ElementType>
                    <ElementValue>1111005</ElementValue>
                  </ElementConcerne>
                </ElementsConcernes>
              </Message>
            </Messages>
            """

        let messages = try AVLXMLParser().parse(data: Data(xml.utf8))

        #expect(messages.count == 1)
        #expect(messages[0].id == "5147")
        #expect(messages[0].title == "Rue Charles Martel mise en sens unique")
        #expect(messages[0].body == "Les lignes 12 et 15 sont deviees.")
        #expect(messages[0].severity == .warning)
        #expect(messages[0].affectedRouteIds == ["12", "15"])
        #expect(messages[0].affectedStopIds == ["1111005"])
        #expect(messages[0].startsAt != nil)
        #expect(messages[0].endsAt != nil)
    }

    @Test func concurrentParsersDoNotShareMutableState() async throws {
        let xml = """
            <Messages>
              <Message>
                <MessageID>concurrent</MessageID>
                <DateDebut>2026-01-12 07:00</DateDebut>
                <Titre>Concurrent alert</Titre>
                <Texte>Parser state stays isolated.</Texte>
              </Message>
            </Messages>
            """
        let data = Data(xml.utf8)

        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    try AVLXMLParser().parse(data: data).count
                }
            }

            var counts: [Int] = []
            for try await count in group {
                counts.append(count)
            }
            return counts
        }

        #expect(counts.allSatisfy { $0 == 1 })
    }
}
