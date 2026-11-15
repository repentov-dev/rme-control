import XCTest
@testable import RME_Control

/// Проверки с настоящей сетью на localhost: UDP-транспорт OSC и HTTP веб-пульта.
@MainActor
final class NetworkIntegrationTests: XCTestCase {
    private func freePort() -> UInt16 { UInt16.random(in: 40000...60000) }

    private func makeClient(sendPort: UInt16, recvPort: UInt16) -> (OSCClient, TestStorage) {
        let t = TestStorage()
        t.defaults.set("127.0.0.1", forKey: "oscHost")
        t.defaults.set(Int(sendPort), forKey: "oscSendPort")
        t.defaults.set(Int(recvPort), forKey: "oscRecvPort")
        return (OSCClient(storage: t.storage), t)
    }

    func testOSCClientLoopback() {
        let port = freePort()
        let (client, storage) = makeClient(sendPort: port, recvPort: port)
        XCTAssertEqual(client.currentRecvPort, port)

        let received = expectation(description: "OSC received")
        client.onFloat = { address, value in
            if address == "/test/value", abs(value - 0.25) < 0.0001 { received.fulfill() }
        }
        client.onString = { _, _ in XCTFail("unexpected string message") }
        client.startListening()
        // Даём listener'у подняться, затем отправляем.
        let ready = expectation(description: "listener ready")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ready.fulfill() }
        wait(for: [ready], timeout: 1)
        client.send("/test/value", 0.25)

        wait(for: [received], timeout: 3)
        XCTAssertLessThan(Date().timeIntervalSince(client.lastReceiveTime), 3)
        client.stopListening()
        _ = storage
    }

    /// Если TotalMix ещё не слушает порт, отправка не ломается: когда он появится, сообщения дойдут.
    func testSendRecoversWhenReceiverAppearsLater() {
        let port = freePort()
        let (sender, s1) = makeClient(sendPort: port, recvPort: freePort())
        sender.send("/early", 1)

        let settle = expectation(description: "first send settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settle.fulfill() }
        wait(for: [settle], timeout: 1)

        let (receiver, s2) = makeClient(sendPort: freePort(), recvPort: port)
        let received = expectation(description: "late message received")
        received.assertForOverFulfill = false
        receiver.onFloat = { address, _ in
            if address == "/late" { received.fulfill() }
        }
        receiver.startListening()

        // Повторяем отправку, как это делает приложение (раз в 5 секунд /sendall).
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated { sender.send("/late", 1) }
        }
        wait(for: [received], timeout: 5)
        timer.invalidate()
        receiver.stopListening()
        sender.stopListening()
        _ = (s1, s2)
    }

    func testWebServerServesPageStateAndActions() throws {
        let f = MixerFixture()
        let server = WebServer(settings: f.settings, state: f.state, mixer: f.mixer)
        let port = freePort()
        server.start(port: port)
        defer { server.stop() }
        let base = "http://127.0.0.1:\(port)"

        let page = String(decoding: try request("\(base)/"), as: UTF8.self)
        XCTAssertTrue(page.contains("RME Control Remote"))
        XCTAssertFalse(page.contains("FADER_CURVE"))

        let stateData = try request("\(base)/api/state")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        XCTAssertEqual(json["connected"] as? Bool, false)
        let outputs = try XCTUnwrap(json["outputs"] as? [[String: Any]])
        XCTAssertEqual(outputs.count, 3)
        XCTAssertEqual(outputs[0]["db"] as? Double ?? 0, -12.13, accuracy: 0.01)
        XCTAssertEqual((json["inputs"] as? [[String: Any]])?.first?["name"] as? String, "Mic 1")

        // Действия применены к моменту ответа — без ожиданий.
        _ = try request("\(base)/api/dim", method: "POST", body: "{}")
        XCTAssertTrue(f.state.dimOn)
        _ = try request("\(base)/api/volume", method: "POST", body: #"{"index":0,"value":0.8}"#)
        XCTAssertEqual(f.state.output(f.outputID(0)).value, 0.8, accuracy: 0.0001)
        _ = try request("\(base)/api/phantom", method: "POST", body: #"{"index":1}"#)
        XCTAssertTrue(f.state.input(f.inputID(1)).phantom)
        _ = try request("\(base)/api/settings", method: "POST", body: #"{"levels":false}"#)
        XCTAssertFalse(f.settings.webShowLevels)
        XCTAssertTrue(f.settings.webShowButtons)

        let levels = try XCTUnwrap(JSONSerialization.jsonObject(with: try request("\(base)/api/levels")) as? [String: Any])
        XCTAssertEqual((levels["levels"] as? [Double])?.count, 4)

        XCTAssertTrue(f.osc.sent.contains { $0.address == "/controlroom/dim" && $0.value == 1 })
        XCTAssertTrue(f.osc.sent.contains { $0.address == "/output/0/faderlin" })
    }

    /// HTTP-запрос с ожиданием, при котором крутится главный run loop
    /// (сервер выполняет действия на MainActor).
    private func request(_ url: String, method: String = "GET", body: String? = nil) throws -> Data {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.httpBody = body.map { Data($0.utf8) }
        let box = ResultBox()
        let done = expectation(description: url)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            box.data = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return try XCTUnwrap(box.data)
    }
}

private final class ResultBox: @unchecked Sendable {
    var data: Data?
}
