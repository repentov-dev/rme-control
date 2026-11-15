import XCTest
@testable import RME_Control

@MainActor
final class ChannelScannerTests: XCTestCase {
    func testOnlyChosenChannelsAreAddedAndConfiguredOnesStayUntouched() {
        let f = MixerFixture()
        let discoveredInputs = [
            DiscoveredChannel(bus: .input, number: 8, name: "TotalMix name"),
            DiscoveredChannel(bus: .input, number: 21, name: "ADAT 1")
        ]
        let discoveredOutputs = [
            DiscoveredChannel(bus: .output, number: 0, name: "Main"),
            DiscoveredChannel(bus: .output, number: 12, name: "ADAT 1")
        ]

        let result = f.mixer.addDiscoveredChannels(inputs: discoveredInputs, outputs: discoveredOutputs)

        XCTAssertEqual(result.addedInputs, 1)
        XCTAssertEqual(result.addedOutputs, 1)
        XCTAssertEqual(f.settings.inputs.count, 5)
        XCTAssertEqual(f.settings.inputs.first?.name ?? "", "Mic 1", "Имя настроенного канала не меняется")
        XCTAssertEqual(f.settings.inputs.last?.oscAddress ?? "", "/input/21")
        XCTAssertTrue(f.settings.inputs.last?.showInPopover ?? false, "Выбранный канал виден в меню")
        XCTAssertEqual(f.settings.outputs.count, 4)
        XCTAssertEqual(f.settings.outputs.last?.oscAddress ?? "", "/output/12")
        XCTAssertTrue(f.settings.outputs.last?.showInMain ?? false, "Выбранный канал виден в меню")
    }
}
