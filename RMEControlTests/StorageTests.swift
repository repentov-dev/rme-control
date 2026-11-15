import XCTest
@testable import RME_Control

@MainActor
final class StorageTests: XCTestCase {
    /// Имена ключей должны совпадать с прежними версиями, иначе пользователи потеряют настройки.
    func testStorageKeysKeepOriginalNames() {
        let expected: Set<String> = [
            "oscHost", "oscSendPort", "oscRecvPort",
            "speakerBAddress", "dimAddress", "monoAddress",
            "inputs", "outputs", "sends",
            "speakerBOn", "dimOn", "monoOn", "phantom", "instrument",
            "showMuteButtons", "showSpeakerB", "showDim", "showMono",
            "showInputCompressor", "showInputEQ", "showOutputCompressor", "showOutputEQ",
            "muteKeyAction", "volumeStepDB", "volumeKeyOutputID", "unmuteOnVolumeChange", "switchOutputWithArrowKeys", "muteOtherOutputsOnSwitch", "useFunctionKeys",
            "hotkeys",
            "setupCompleted",
            "watchDeviceConnection",
            "settingsPresets",
            "appLanguage",
            "webServerEnabled", "webServerPort", "webShowButtons", "webShowInputs", "webShowLevels",
            "inputNames", "showPhantom1", "showPhantom2", "showPhantom3", "showPhantom4"
        ]
        XCTAssertEqual(Set(StorageKey.allCases.map(\.rawValue)), expected)
    }

    func testFirstLaunchHasNoChannelsAndNeedsSetup() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)

        // На свежей установке каналов нет: их выбирают в мастере (Scan channels).
        XCTAssertTrue(settings.inputs.isEmpty)
        XCTAssertTrue(settings.outputs.isEmpty)
        XCTAssertNil(settings.volumeKeyOutputID)
        XCTAssertTrue(settings.needsSetup)
        XCTAssertEqual(settings.speakerBAddress, "/controlroom/speakerb")
        XCTAssertEqual(settings.dimAddress, "/controlroom/dim")
        XCTAssertEqual(settings.monoAddress, "/controlroom/mainmono")
        XCTAssertEqual(settings.language, .english)
        XCTAssertTrue(settings.watchDeviceConnection)
        XCTAssertEqual(settings.volumeStepDB, 2)
        XCTAssertEqual(settings.webServerPort, 8080)
        XCTAssertEqual(settings.muteKeyAction, .dim)
        XCTAssertTrue(settings.unmuteOnVolumeChange)
        XCTAssertFalse(settings.switchOutputWithArrowKeys)
        XCTAssertFalse(settings.muteOtherOutputsOnSwitch)
        // Пустые списки каналов не сохраняются: отсутствие ключа означает «ещё не настроено».
        XCTAssertNil(t.defaults.data(forKey: "inputs"))
        XCTAssertNil(t.defaults.data(forKey: "outputs"))
        XCTAssertNil(t.defaults.object(forKey: "showDim"))
    }

    /// Удалённые пользователем каналы не должны возвращаться при следующем запуске.
    func testEmptyChannelListsStayEmptyAfterRestart() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        settings.inputs = []
        settings.outputs = []
        settings.completeSetup()

        let reloaded = AppSettings(storage: t.storage)
        XCTAssertTrue(reloaded.inputs.isEmpty)
        XCTAssertTrue(reloaded.outputs.isEmpty)
        XCTAssertFalse(reloaded.needsSetup)
    }

    func testCompletingSetupStopsTheWizard() {
        let t = TestStorage()
        let settings = AppSettings(storage: t.storage)

        XCTAssertTrue(settings.needsSetup)
        settings.completeSetup()
        XCTAssertFalse(settings.needsSetup)

        let reloaded = AppSettings(storage: t.storage)
        XCTAssertFalse(reloaded.needsSetup)
    }

    func testSelectAdjacentVolumeKeyOutputWraps() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        let ids = settings.outputs.map(\.id)

        XCTAssertEqual(settings.volumeKeyOutputID, ids[0])
        settings.selectAdjacentVolumeKeyOutput(offset: 1)
        XCTAssertEqual(settings.volumeKeyOutputID, ids[1])
        settings.selectAdjacentVolumeKeyOutput(offset: -1)
        XCTAssertEqual(settings.volumeKeyOutputID, ids[0])
        settings.selectAdjacentVolumeKeyOutput(offset: -1)
        XCTAssertEqual(settings.volumeKeyOutputID, ids[2])
    }

    func testSettingsPresetSavesAndRestoresChannels() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        let outputID = settings.outputs[0].id
        settings.updateOutput(outputID) {
            $0.name = "Studio A"
            $0.oscAddress = "/output/2"
        }
        settings.updateInput(settings.inputs[0].id) { $0.name = "Vocal" }
        settings.savePreset(named: "Studio")

        settings.updateOutput(outputID) { $0.name = "Changed" }
        settings.updateInput(settings.inputs[0].id) { $0.name = "Changed" }

        let reloaded = AppSettings(storage: t.storage)
        XCTAssertEqual(reloaded.presets.map(\.name), ["Studio"])
        reloaded.apply(reloaded.presets[0])
        XCTAssertEqual(reloaded.outputs[0].name, "Studio A")
        XCTAssertEqual(reloaded.outputs[0].oscAddress, "/output/2")
        XCTAssertEqual(reloaded.inputs[0].name, "Vocal")
    }

    func testSettingPresetWithSameNameUpdatesIt() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        settings.savePreset(named: "Live")
        settings.updateOutput(settings.outputs[0].id) { $0.name = "Live Main" }
        settings.savePreset(named: "live")

        XCTAssertEqual(settings.presets.count, 1)
        XCTAssertEqual(settings.presets[0].snapshot.outputs[0].name, "Live Main")
    }

    func testLegacyValuesAreMigrated() {
        let t = TestStorage()
        t.defaults.set(["Vocal", "Bass"], forKey: "inputNames")
        t.defaults.set(false, forKey: "showPhantom2")
        t.defaults.set("/1/mainDim", forKey: "dimAddress")
        t.defaults.set("/1/mainMono", forKey: "monoAddress")
        t.defaults.set("/custom/speakerb", forKey: "speakerBAddress")

        let settings = AppSettings(storage: t.storage)

        XCTAssertEqual(settings.inputs.map(\.name), ["Vocal", "Bass", "Mic 3", "Guitar"])
        XCTAssertEqual(settings.inputs.map(\.showInMain), [true, false, true, true])
        XCTAssertEqual(settings.dimAddress, "/controlroom/dim")
        XCTAssertEqual(settings.monoAddress, "/controlroom/mainmono")
        XCTAssertEqual(settings.speakerBAddress, "/custom/speakerb")
    }

    func testLegacyHasPreampsIsDecoded() {
        let json = #"[{"name":"Old","oscAddress":"/input/3","hasPreamps":true},{"name":"Line","oscAddress":"/input/4","hasPreamps":false}]"#
        let t = TestStorage()
        t.defaults.set(Data(json.utf8), forKey: "inputs")

        let settings = AppSettings(storage: t.storage)

        XCTAssertEqual(settings.inputs.map(\.type), [.micPhantomInstrument, .line])
        XCTAssertEqual(settings.inputs[0].resolvedLevelAddress, "/level/in/3")
    }

    func testLevelAddressFollowsChannelNumber() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        let input = settings.inputs[0]
        settings.updateInput(input.id) { $0.oscAddress = "/input/21" }
        settings.updateOutput(settings.outputs[0].id) { $0.oscAddress = "/output/9" }

        XCTAssertEqual(settings.inputs[0].resolvedLevelAddress, "/level/in/21")
        XCTAssertEqual(settings.outputs[0].resolvedLevelAddress, "/level/out/9")
    }

    func testChangesArePersistedUnderOriginalKeys() {
        let t = TestStorage()
        let settings = makeConfiguredSettings(t)
        settings.showDim = false
        settings.volumeStepDB = 5
        settings.webServerPort = 9090
        settings.muteKeyAction = .mute
        settings.updateOutput(settings.outputs[0].id) { $0.name = "Monitors" }

        XCTAssertFalse(t.defaults.bool(forKey: "showDim"))
        XCTAssertEqual(t.defaults.double(forKey: "volumeStepDB"), 5)
        XCTAssertEqual(t.defaults.integer(forKey: "webServerPort"), 9090)
        XCTAssertEqual(t.defaults.string(forKey: "muteKeyAction"), "mute")

        let reloaded = AppSettings(storage: t.storage)
        XCTAssertFalse(reloaded.showDim)
        XCTAssertEqual(reloaded.volumeStepDB, 5)
        XCTAssertEqual(reloaded.webServerPort, 9090)
        XCTAssertEqual(reloaded.muteKeyAction, .mute)
        XCTAssertEqual(reloaded.outputs[0].name, "Monitors")
    }

    /// Живое состояние пульта больше не пишется в UserDefaults, а старые значения не читаются.
    func testLiveStateIsNotPersisted() {
        let f = MixerFixture()
        f.testStorage.defaults.set(true, forKey: "dimOn")
        f.mixer.toggleMono()
        f.mixer.togglePhantom(inputID: f.inputID(0))

        XCTAssertNil(f.testStorage.defaults.object(forKey: "monoOn"))
        XCTAssertNil(f.testStorage.defaults.object(forKey: "phantom"))
        XCTAssertFalse(MixerState().dimOn)
    }
}
