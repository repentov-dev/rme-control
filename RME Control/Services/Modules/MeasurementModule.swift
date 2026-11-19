import Foundation
import Observation

/// Модуль замера: `roomeq` и `sotf-capture` вне бандла. Приходит одним
/// архивом с GitHub Releases, ставится в Application Support и удаляется
/// из настроек — приложение от этого не тяжелеет.
@MainActor
@Observable
final class MeasurementModule {
    static let shared = MeasurementModule()

    /// Версия, которая вшита в сборку приложения (базовая).
    nonisolated static let version = "1.1"
    /// Файл с версией установленного модуля: после обновления он новее базовой.
    nonisolated static var versionFile: URL { root.appendingPathComponent("Modules/version.txt") }
    /// Версия того, что реально лежит на диске.
    nonisolated static var installedVersion: String {
        guard let text = try? String(contentsOf: versionFile, encoding: .utf8) else { return version }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? version : trimmed
    }
    /// Один архив на весь модуль: внутри `roomeq` и `sotf-capture`.
    nonisolated static let archiveURL = URL(string:
        "https://github.com/repentov-dev/rme-control/releases/download/measure-\(version)/measure-\(version).zip")!
    /// Тег последнего релиза модуля, по нему проверяются обновления.
    nonisolated static let latestAPI = URL(string:
        "https://api.github.com/repos/repentov-dev/rme-control/releases")!

    enum Phase: Equatable {
        case missing
        case installed
        case downloading(Double)
        case failed(String)
    }

    private(set) var phase: Phase = .missing
    /// Версия новее установленной, найденная на GitHub.
    private(set) var updateVersion: String?
    /// Адрес архива найденного обновления.
    private(set) var updateURL: URL?
    enum CheckResult: Equatable { case upToDate, available, failed }
    private(set) var checkResult: CheckResult?
    private(set) var isChecking = false
    private(set) var sizeBytes: Int64 = 0

    nonisolated static let binaryNames = ["roomeq", "sotf-capture"]

    private init() {
        Self.migrateLegacyLayout()
        refreshPhase()
    }

    // MARK: - Где лежит

    /// Все файлы приложения — в Application Support: папка «Документы» под TCC,
    /// из-за неё загрузка молча падала без разрешения на доступ к файлам.
    nonisolated static var root: URL {
        // Переопределение для тестов: позволяет проверить установку и удаление
        // во временной папке, не трогая реальный модуль пользователя.
        if let override = ProcessInfo.processInfo.environment["RME_MODULE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("RME Control", isDirectory: true)
    }

    /// Каталог установленного модуля. Один на все версии: версию помнит
    /// `version.txt`, поэтому обновление не плодит папки.
    nonisolated static var installDirectory: URL {
        root.appendingPathComponent("Modules/current", isDirectory: true)
    }

    /// Собирает любую старую раскладку `Modules/<версия>` в `Modules/current`:
    /// иначе оставшаяся папка прошлой версии считалась установленным модулем
    /// и мешала удалению.
    private static func migrateLegacyLayout() {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: installDirectory.path) else { return }
        let modules = root.appendingPathComponent("Modules", isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(at: modules,
                                                            includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let legacy = entries
            .filter { entry in
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    && entry.lastPathComponent != "current"
                    && binaryNames.allSatisfy {
                        fileManager.isExecutableFile(atPath: entry.appendingPathComponent($0).path)
                    }
            }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        guard let newest = legacy.last else { return }
        try? fileManager.createDirectory(at: installDirectory.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        guard (try? fileManager.moveItem(at: newest, to: installDirectory)) != nil else { return }
        let name = newest.lastPathComponent
        if name.first?.isNumber == true {
            try? name.write(to: versionFile, atomically: true, encoding: .utf8)
        }
        // Прочие старые папки больше не нужны.
        for entry in entries where entry.lastPathComponent != "current" && entry != newest {
            try? fileManager.removeItem(at: entry)
        }
    }

    /// Скачанный архив держим на диске: переустановка идёт без сети.
    nonisolated static var cachedArchive: URL {
        root.appendingPathComponent("Modules/measure-\(version).zip")
    }

    /// Бинарник модуля: `Modules/current`, иначе запасной вариант в бандле.
    /// Старые раскладки сначала переносятся в `current` при запуске.
    nonisolated static func binary(named name: String) -> URL? {
        let installed = installDirectory.appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: installed.path) { return installed }
        return Bundle.main.url(forResource: name, withExtension: nil)
    }

    nonisolated static var isInstalled: Bool {
        binaryNames.allSatisfy {
            FileManager.default.isExecutableFile(
                atPath: installDirectory.appendingPathComponent($0).path)
        }
    }

    // MARK: - Состояние

    func refreshPhase() {
        phase = Self.isInstalled ? .installed : .missing
        sizeBytes = Self.installedSize()
    }

    private nonisolated static func installedSize() -> Int64 {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: installDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    // MARK: - Загрузка

    /// Скачивает архив модуля и возвращает файл на диске.
    private func fetchArchive(url: URL, version: String) async throws -> URL {
        let destination = Self.root.appendingPathComponent("Modules/measure-\(version).zip")
        let downloader = ArchiveDownloader(destination: destination) { [weak self] value in
            Task { @MainActor [weak self] in
                self?.phase = .downloading(value)
            }
        }
        let file = try await downloader.download(url: url)
        phase = .downloading(1)
        return file
    }

    /// Первичная установка базовой версии с GitHub.
    func download() async {
        if case .downloading = phase { return }
        phase = .downloading(0)
        do {
            let archive = try await fetchArchive(url: Self.archiveURL, version: Self.version)
            try install(from: archive, version: Self.version)
            refreshPhase()
        } catch {
            fail(error)
        }
    }

    /// Установка найденного обновления.
    func installUpdate() async {
        guard let url = updateURL, let version = updateVersion else { return }
        phase = .downloading(0)
        do {
            let archive = try await fetchArchive(url: url, version: version)
            try install(from: archive, version: version)
            updateVersion = nil
            updateURL = nil
            refreshPhase()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        NSLog("measure module: %@", String(describing: error))
        if case ModuleError.http(404) = error {
            phase = .failed(String(localized: "The module release is not published on GitHub yet."))
        } else {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Установка из уже скачанного архива: работает и без релиза на GitHub.
    func install(fromLocalArchive url: URL) {
        do {
            try install(from: url, version: Self.version)
            refreshPhase()
        } catch {
            fail(error)
        }
    }

    private func install(from archive: URL, version: String) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("measure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archive.path, staging.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw ModuleError.unzip }

        let target = Self.installDirectory
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)
        for name in Self.binaryNames {
            let binary = target.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: binary.path) else { throw ModuleError.incomplete }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        }
        try FileManager.default.createDirectory(at: Self.versionFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try version.write(to: Self.versionFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Удаление и обновления

    /// Удаляет модуль целиком: распакованные файлы и скачанный архив,
    /// а также следы старых установок в бандле и Application Support.
    func remove() {
        let fileManager = FileManager.default
        let modules = Self.root.appendingPathComponent("Modules", isDirectory: true)

        // Сносим всё содержимое `Modules`: `current`, старые версии вида
        // `Modules/<версия>` и скачанные архивы. Раньше удалялся только
        // `current`, а оставшаяся старая папка снова считалась установкой.
        let entries = (try? fileManager.contentsOfDirectory(at: modules,
                                                           includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
        try? fileManager.removeItem(at: Self.versionFile)

        // Следы прежних установок вне рабочей папки.
        let legacy = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Modules/\(Self.version)"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/RME Control/Modules/\(Self.version)"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/RME Control/Modules/measure-\(Self.version).zip"),
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/RME Control/Modules")
        ]
        for url in legacy where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }

        updateVersion = nil
        updateURL = nil
        checkResult = nil
        phase = .missing
        refreshPhase()
        NSLog("measure module: removed, installed = %@", Self.isInstalled ? "yes" : "no")
    }

    /// Проверка релизов `measure-*` на GitHub. Без `force` — не чаще раза в сутки.
    func checkForUpdates(force: Bool = false) async {
        let key = "measureModuleCheckedAt"
        let last = UserDefaults.standard.double(forKey: key)
        guard force || Date().timeIntervalSince1970 - last > 86_400 else { return }
        guard !isChecking else { return }

        isChecking = true
        checkResult = nil
        defer { isChecking = false }

        guard let (data, _) = try? await URLSession.shared.data(from: Self.latestAPI),
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            checkResult = .failed
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)

        var newest: (version: String, url: URL)?
        for release in releases {
            guard let tag = release["tag_name"] as? String, tag.hasPrefix("measure-") else { continue }
            let version = String(tag.dropFirst("measure-".count))
            guard version.compare(Self.installedVersion, options: .numeric) == .orderedDescending else { continue }
            guard let assets = release["assets"] as? [[String: Any]],
                  let asset = assets.first(where: { ($0["name"] as? String) == "measure-\(version).zip" }),
                  let link = asset["browser_download_url"] as? String,
                  let url = URL(string: link) else { continue }
            if newest == nil || version.compare(newest!.version, options: .numeric) == .orderedDescending {
                newest = (version, url)
            }
        }

        updateVersion = newest?.version
        updateURL = newest?.url
        checkResult = newest == nil ? .upToDate : .available
    }

    enum ModuleError: LocalizedError {
        case http(Int)
        case unzip
        case incomplete

        var errorDescription: String? {
            switch self {
            case .http(let code): return String(localized: "Download failed (HTTP \(code)).")
            case .unzip: return String(localized: "Could not unpack the module archive.")
            case .incomplete: return String(localized: "The archive does not contain the measurement engines.")
            }
        }
    }
}

/// Загрузчик архива с прогрессом: `URLSession` с делегатом отдаёт проценты,
/// а файл кладёт сразу на диск.
private final class ArchiveDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var failure: Error?
    private var session: URLSession?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            failure = MeasurementModule.ModuleError.http(http.statusCode)
            return
        }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let result = failure ?? error {
            continuation?.resume(throwing: result)
        } else {
            continuation?.resume(returning: destination)
        }
        continuation = nil
    }
}
