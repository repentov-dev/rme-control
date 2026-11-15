import XCTest
import Combine
import Observation
@testable import RME_Control

@MainActor
final class MixerServiceTests: XCTestCase {
    func testIncomingVolumeMovesFaderUnlessDragging() {
        let f = MixerFixture()
        let main = f.outputID(0)
        f.mixer.handleOSCFloat("/output/0/volume", -12.13)
        XCTAssertEqual(f.state.output(main).db, -12.13, accuracy: 0.001)
        XCTAssertEqual(f.state.output(main).value, 0.5, accuracy: 0.01)

        f.mixer.handleOSCFloat("/output/0/volume", -20)
        XCTAssertLessThan(f.state.output(main).value, 0.45)

        f.state.mainDragInProgress = true
        let before = f.state.output(main).value
        f.mixer.handleOSCFloat("/output/0/volume", 6)
        XCTAssertEqual(f.state.output(main).value, before)
        XCTAssertEqual(f.state.output(main).db, 6, "dB обновляется даже во время перетаскивания")
    }

    func testIncomingButtonsAndPreamps() {
        let f = MixerFixture()
        f.mixer.handleOSCFloat("/output/8/mute", 1)
        f.mixer.handleOSCFloat("/controlroom/dim", 1)
        f.mixer.handleOSCFloat("/controlroom/mainmono", 1)
        f.mixer.handleOSCFloat("/controlroom/speakerb", 1)
        f.mixer.handleOSCFloat("/input/9/48v", 1)
        f.mixer.handleOSCFloat("/input/11/instrument", 1)

        XCTAssertEqual(f.settings.outputs.map { f.state.output($0.id).muted }, [false, true, false])
        XCTAssertTrue(f.state.dimOn)
        XCTAssertTrue(f.state.monoOn)
        XCTAssertTrue(f.state.speakerBOn)
        XCTAssertEqual(f.settings.inputs.map { f.state.input($0.id).phantom }, [false, true, false, false])
        XCTAssertEqual(f.settings.inputs.map { f.state.input($0.id).instrument }, [false, false, false, true])
    }

    /// Изменения, сделанные в самом TotalMix, должны показывать HUD в приложении.
    func testIncomingStateChangesTriggerHUDEvents() {
        let f = MixerFixture()
        var volumes: [UUID] = []
        var dims: [Bool] = []
        var monos: [Bool] = []
        let c1 = f.mixer.outputVolumeChangedTrigger.sink { volumes.append($0) }
        let c2 = f.mixer.dimChangedTrigger.sink { dims.append($0) }
        let c3 = f.mixer.monoChangedTrigger.sink { monos.append($0) }

        f.mixer.handleOSCFloat("/output/0/volume", -10)
        f.mixer.handleOSCFloat("/output/0/volume", -10.001)
        f.mixer.handleOSCFloat("/output/8/volume", -20)
        f.mixer.handleOSCFloat("/controlroom/dim", 1)
        f.mixer.handleOSCFloat("/controlroom/dim", 1)
        f.mixer.handleOSCFloat("/controlroom/mainmono", 1)
        f.mixer.handleOSCFloat("/controlroom/mainmono", 0)

        XCTAssertEqual(volumes, [f.outputID(0), f.outputID(1)])
        XCTAssertEqual(dims, [true])
        XCTAssertEqual(monos, [true, false])
        _ = (c1, c2, c3)
    }

    /// Ответ на /sendall не должен показывать HUD: это синхронизация, а не действие пользователя.
    func testStateSyncVolumeChangesDoNotTriggerHUDEvents() {
        let f = MixerFixture()
        var volumes: [UUID] = []
        let c = f.mixer.outputVolumeChangedTrigger.sink { volumes.append($0) }

        f.mixer.requestState()
        f.mixer.handleOSCFloat("/output/0/volume", -10)

        XCTAssertTrue(volumes.isEmpty)
        XCTAssertEqual(f.state.output(f.outputID(0)).db, -10, accuracy: 0.001)
        _ = c
    }

    /// Локальные переключения Dim/Mono тоже должны показывать HUD.
    func testLocalDimAndMonoChangesTriggerHUDEvents() {
        let f = MixerFixture()
        var dims: [Bool] = []
        var monos: [Bool] = []
        let c1 = f.mixer.dimChangedTrigger.sink { dims.append($0) }
        let c2 = f.mixer.monoChangedTrigger.sink { monos.append($0) }

        f.mixer.toggleDim()
        f.mixer.toggleMono()

        XCTAssertEqual(dims, [true])
        XCTAssertEqual(monos, [true])
        _ = (c1, c2)
    }

    func testLevelsAndClipTrigger() {
        let f = MixerFixture()
        var clipped: [UUID] = []
        let c = f.mixer.clipTrigger.sink { clipped.append($0) }

        f.mixer.handleOSCFloat("/level/in/9", -20)
        f.mixer.handleOSCFloat("/level/in/8", 0.5)

        let throttled = expectation(description: "levels reach UI after throttle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { throttled.fulfill() }
        wait(for: [throttled], timeout: 2)

        XCTAssertEqual(clipped, [f.inputID(0)])
        XCTAssertEqual(f.state.level(f.inputID(0)), 0.5)
        XCTAssertEqual(f.state.level(f.inputID(1)), -20)
        XCTAssertEqual(f.state.level(f.inputID(2)), MixerState.silentLevel)
        _ = c
    }

    func testDeviceConnectionEvents() {
        let f = MixerFixture()
        var events: [String] = []
        let c1 = f.mixer.deviceConnectedTrigger.sink { events.append("+\($0)") }
        let c2 = f.mixer.deviceDisconnectedTrigger.sink { events.append("-\($0)") }

        f.mixer.handleOSCString("/status/device", "Fireface 802 FS (23825621)")
        f.mixer.handleOSCFloat("/status/connection", 1)
        f.mixer.handleOSCFloat("/status/connection", 1)
        f.mixer.handleOSCFloat("/status/connection", 0)

        XCTAssertEqual(events, ["+Fireface 802 FS", "-Fireface 802 FS"])
        XCTAssertEqual(f.osc.sent.filter { $0.address == "/sendall" }.count, 1)
        _ = (c1, c2)
    }

    func testToggleCommandsSendToConfiguredAddresses() {
        let f = MixerFixture()
        f.settings.dimAddress = "/custom/dim"

        f.mixer.toggleDim()
        XCTAssertTrue(f.state.dimOn)
        XCTAssertEqual(f.osc.last?.address, "/custom/dim")
        XCTAssertEqual(f.osc.last?.value, 1)

        f.mixer.toggleMono()
        XCTAssertEqual(f.osc.last?.address, "/controlroom/mainmono")

        f.mixer.togglePhantom(inputID: f.inputID(0))
        XCTAssertEqual(f.osc.last?.address, "/input/8/48v")
        XCTAssertEqual(f.osc.last?.value, 1)

        f.mixer.toggleInstrument(inputID: f.inputID(0))
        XCTAssertEqual(f.osc.last?.address, "/input/8/instrument")

        let sentBefore = f.osc.sent.count
        f.mixer.togglePhantom(inputID: f.inputID(3))
        XCTAssertEqual(f.osc.sent.count, sentBefore, "у гитарного входа нет +48V")
    }

    func testCompressorCommandsAndFeedback() {
        let f = MixerFixture()
        let mic = f.inputID(0)

        f.mixer.toggleCompressor(inputID: mic)
        XCTAssertTrue(f.state.input(mic).compressor.enabled)
        XCTAssertEqual(f.osc.last?.address, "/input/8/dynamics/enable")
        XCTAssertEqual(f.osc.last?.value, 1)

        f.mixer.setCompressorParameter(inputID: mic, parameter: .threshold, value: -18)
        XCTAssertEqual(f.osc.last?.address, "/input/8/dynamics/compthres")
        XCTAssertEqual(f.state.input(mic).compressor.threshold, -18, accuracy: 0.001)

        f.mixer.setCompressorParameter(inputID: mic, parameter: .ratio, value: 4)
        XCTAssertEqual(f.osc.last?.address, "/input/8/dynamics/compratio")

        f.mixer.setCompressorParameter(inputID: mic, parameter: .attack, value: 999)
        XCTAssertEqual(f.state.input(mic).compressor.attack, 200, "значение ограничивается диапазоном")

        f.mixer.handleOSCFloat("/input/8/dynamics/gain", 6)
        XCTAssertEqual(f.state.input(mic).compressor.gain, 6, accuracy: 0.001)

        let sentBefore = f.osc.sent.count
        f.mixer.toggleCompressor(inputID: f.inputID(3))
        XCTAssertEqual(f.osc.sent.count, sentBefore, "у гитарного входа нет компрессора")
    }

    func testCompressorGainReductionCurve() {
        var compressor = CompressorState()
        compressor.enabled = true
        compressor.threshold = -20
        compressor.ratio = 4

        XCTAssertEqual(compressor.gainReduction(forInputLevel: -10), 7.5, accuracy: 0.001)
        XCTAssertEqual(compressor.gainReduction(forInputLevel: -30), 0, "ниже порога сжатия нет")

        compressor.enabled = false
        XCTAssertEqual(compressor.gainReduction(forInputLevel: 0), 0)
    }

    func testStepVolumeUnmutesAndMovesByStep() {
        let f = MixerFixture()
        let main = f.outputID(0)
        f.state.updateOutput(main) { $0.muted = true }

        f.mixer.stepVolume(outputID: main, byDB: 2)

        XCTAssertFalse(f.state.output(main).muted)
        XCTAssertEqual(f.osc.sent.map(\.address), ["/output/0/mute", "/output/0/faderlin"])
        XCTAssertEqual(FaderMath.db(for: f.state.output(main).value), -10.13, accuracy: 0.1)
    }

    func testStepVolumeKeepsMuteWhenUnmuteSettingIsOff() {
        let f = MixerFixture()
        let main = f.outputID(0)
        f.settings.unmuteOnVolumeChange = false
        f.state.updateOutput(main) { $0.muted = true }

        f.mixer.stepVolume(outputID: main, byDB: 2)

        XCTAssertTrue(f.state.output(main).muted)
        XCTAssertEqual(f.osc.sent.map(\.address), ["/output/0/faderlin"])
        XCTAssertEqual(FaderMath.db(for: f.state.output(main).value), -10.13, accuracy: 0.1)
    }

    func testMuteOtherOutputsKeepsOnlySelectedOutputAudible() {
        let f = MixerFixture()
        let main = f.outputID(0)
        let phones1 = f.outputID(1)
        let phones2 = f.outputID(2)
        f.state.updateOutput(main) { $0.muted = true }

        f.mixer.muteOtherOutputs(except: phones1)

        XCTAssertFalse(f.state.output(phones1).muted)
        XCTAssertTrue(f.state.output(main).muted)
        XCTAssertTrue(f.state.output(phones2).muted)

        f.mixer.muteOtherOutputs(except: phones2)

        XCTAssertTrue(f.state.output(main).muted)
        XCTAssertTrue(f.state.output(phones1).muted)
        XCTAssertFalse(f.state.output(phones2).muted)
    }

    func testSetVolumeUnmutesOnlyWhenUnmuteSettingIsOn() {
        let f = MixerFixture()
        let main = f.outputID(0)
        f.state.updateOutput(main) { $0.muted = true }

        f.settings.unmuteOnVolumeChange = false
        f.mixer.setVolume(outputID: main, value: 0.5)
        XCTAssertTrue(f.state.output(main).muted)
        XCTAssertEqual(f.osc.last?.address, "/output/0/faderlin")

        f.settings.unmuteOnVolumeChange = true
        f.mixer.setVolume(outputID: main, value: 0.6)
        XCTAssertFalse(f.state.output(main).muted)
        XCTAssertEqual(f.osc.sent.suffix(2).map(\.address), ["/output/0/mute", "/output/0/faderlin"])
    }

    func testSetVolumeClampsAndIgnoresUnknownChannel() {
        let f = MixerFixture()
        f.mixer.setVolume(outputID: f.outputID(1), value: 1.7)
        XCTAssertEqual(f.state.output(f.outputID(1)).value, 1)
        XCTAssertEqual(f.osc.last?.address, "/output/8/faderlin")
        XCTAssertEqual(f.osc.last?.value, 1)

        let sentBefore = f.osc.sent.count
        f.mixer.setVolume(outputID: UUID(), value: 0.3)
        XCTAssertEqual(f.osc.sent.count, sentBefore)
    }

    /// Состояние привязано к id: удаление канала не сдвигает состояние соседних.
    func testRemovingChannelKeepsOtherStates() {
        let f = MixerFixture()
        let phones2 = f.outputID(2)
        f.mixer.setMuted(outputID: phones2, muted: true)
        f.settings.volumeKeyOutputID = f.outputID(0)

        f.mixer.removeOutput(id: f.outputID(0))

        XCTAssertEqual(f.settings.outputs.count, 2)
        XCTAssertEqual(f.state.outputs.count, 2)
        XCTAssertTrue(f.state.output(phones2).muted)
        XCTAssertEqual(f.settings.volumeKeyOutputID, f.settings.outputs[0].id)

        f.mixer.addOutput()
        XCTAssertEqual(f.settings.outputs.last?.oscAddress, "/output/2")
        XCTAssertEqual(f.state.outputs.count, 3)

        f.mixer.addInput()
        XCTAssertEqual(f.settings.inputs.last?.oscAddress, "/input/12")
        XCTAssertEqual(f.state.inputs.count, 5)
        f.mixer.removeInput(id: f.inputID(4))
        XCTAssertEqual(f.state.inputs.count, 4)
    }

    func testResetToDefaults() {
        let f = MixerFixture()
        f.mixer.addOutput()
        f.settings.showDim = false
        f.settings.webServerPort = 1234

        f.mixer.resetToDefaults()

        XCTAssertEqual(f.settings.outputs.count, 3)
        XCTAssertEqual(Set(f.state.outputs.keys), Set(f.settings.outputs.map(\.id)))
        XCTAssertTrue(f.settings.showDim)
        XCTAssertEqual(f.settings.webServerPort, 8080)
        XCTAssertNil(f.settings.volumeKeyOutputID)
        XCTAssertEqual(f.settings.volumeKeyOutput?.id, f.settings.outputs.first?.id)
    }

    func testConnectionMonitor() {
        let f = MixerFixture()
        var lastReceive = Date()
        var connectedCalls = 0
        let monitor = ConnectionMonitor(settings: f.settings, state: f.state, lastReceiveTime: { lastReceive }, onConnected: { connectedCalls += 1 })

        monitor.update()
        XCTAssertFalse(f.state.isConnected, "TotalMix жив, но устройства нет")
        XCTAssertTrue(f.state.deviceOffline)

        f.state.devicePresent = true
        monitor.update()
        XCTAssertTrue(f.state.isConnected)
        XCTAssertEqual(connectedCalls, 1)

        lastReceive = Date().addingTimeInterval(-10)
        monitor.update()
        XCTAssertFalse(f.state.isConnected)
    }
}

@MainActor
final class ObservationTests: XCTestCase {
    func testViewModelReadsAreTracked() {
        let f = MixerFixture()
        let vm = MixerViewModel(settings: f.settings, state: f.state, mixer: f.mixer)
        XCTAssertEqual(vm.popoverInputRows, [Array(f.settings.inputs.prefix(3).map(\.id))])

        let changed = Flag()
        withObservationTracking { _ = vm.dimOn } onChange: { changed.value = true }
        f.state.dimOn = true
        XCTAssertTrue(changed.value)
    }

    /// Уровни входов — отдельное свойство: их обновление не трогает View, читающие кнопки.
    func testLevelUpdatesDoNotInvalidateButtons() {
        let f = MixerFixture()
        let vm = MixerViewModel(settings: f.settings, state: f.state, mixer: f.mixer)
        let buttonsChanged = Flag()
        withObservationTracking { _ = (vm.dimOn, vm.outputValue(f.outputID(0))) } onChange: { buttonsChanged.value = true }

        f.mixer.handleOSCFloat("/level/in/8", -6)
        let throttled = expectation(description: "throttle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { throttled.fulfill() }
        wait(for: [throttled], timeout: 2)

        XCTAssertEqual(f.state.level(f.inputID(0)), -6)
        XCTAssertFalse(buttonsChanged.value)
    }

    func testObserveHelperDeliversInitialAndChanges() {
        let f = MixerFixture()
        let values = Recorder()
        let state = f.state
        let changed = expectation(description: "change delivered")
        RME_Control.observe({ state.dimOn }) { value in
            values.items.append(value)
            if values.items.count == 2 { changed.fulfill() }
        }
        state.dimOn = true
        wait(for: [changed], timeout: 2)
        XCTAssertEqual(values.items, [false, true])
    }
}

/// Изменяемые значения для замыканий наблюдения в тестах (все обращения — на главном потоке).
private final class Flag: @unchecked Sendable {
    var value = false
}

private final class Recorder: @unchecked Sendable {
    var items: [Bool] = []
}
