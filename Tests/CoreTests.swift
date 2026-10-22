import Foundation
import Darwin

@main
struct CoreTests {
    static var failures = 0
    static var checks = 0
    static let fixtures = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RARX_FIXTURES"] ?? "Tests/Fixtures")
    static let enginePath = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RARX_ENGINE"] ?? "vendor/unrar/unrar")

    static func main() async {
        let logPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("rarx-coretest-\(UUID().uuidString).log")
        setenv("RARX_LOG_PATH", logPath.path, 1)

        print("RARx core tests")
        print("fixtures: \(fixtures.path)")
        print("engine:   \(enginePath.path)")

        guard FileManager.default.isExecutableFile(atPath: enginePath.path) else {
            print("FATAL: engine is not executable")
            exit(2)
        }

        let engine = UnrarEngine(executableURL: enginePath)
        let service = SafeExtractionService(engine: engine)

        await testEngineVersion(engine)
        await testInspectSample(engine)
        await testExtractSample(service)
        await testCollisionSafety(service)
        await testEncryptedHeaders(engine, service)
        await testEncryptedData(engine, service)
        await testSplitVolumes(engine, service)
        await testUnsafeLinks(service)
        await testFoldersOnly(service)
        await testInvalidArchives(engine)
        testVolumeResolution()
        await testMissingSecondVolume(service)
        await testStaleStagingCleanup(service)
        testNoPasswordInLog(logPath)

        AppLog.flush()
        try? FileManager.default.removeItem(at: logPath)

        print("\n\(checks) checks, \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Tests

    static func testEngineVersion(_ engine: UnrarEngine) async {
        section("engine version")
        if let version = engine.version() {
            check(version.contains("UNRAR"), "version string: \(version)")
        } else {
            check(false, "engine did not report a version")
        }
    }

    static func testInspectSample(_ engine: UnrarEngine) async {
        section("inspect sample")
        do {
            let listing = try await engine.inspect(archive: fixture("sample.rar"), password: nil)
            check(listing.format.contains("RAR 5"), "format is RAR 5")
            check(listing.entries.count >= 7, "entries >= 7 (got \(listing.entries.count))")
            check(listing.encryptedHeaders == false, "headers not encrypted")
            check(listing.encryptedEntries == false, "entries not encrypted")
            check(listing.totalUncompressedSize > 16_000, "uncompressed size plausible (\(listing.totalUncompressedSize))")
            check(listing.fileCount == 6, "six file entries (got \(listing.fileCount))")
            check(listing.entries.contains { $0.path == "资料 folder/中文 文档.txt" }, "unicode path preserved")
            check(listing.entries.contains { $0.kind == .directory && $0.path == "empty" }, "empty directory listed")
            check(listing.entries.contains { $0.kind == .symbolicLink } == false, "sample has no symlink entries")
        } catch {
            check(false, "inspect sample threw: \(error)")
        }
    }

    static func testExtractSample(_ service: SafeExtractionService) async {
        section("extract sample")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        var progress: [Double] = []

        do {
            let result = try await service.extract(
                archive: fixture("sample.rar"),
                listing: try await serviceListing("sample.rar"),
                password: nil,
                destination: destination
            ) { update in
                progress.append(update.fractionCompleted)
            }
            check(result.extractedFileCount >= 6, "files extracted (\(result.extractedFileCount))")
            check(readText(destination.appendingPathComponent("readme.txt")) == "hello RAR\n", "readme content")
            check(readText(destination.appendingPathComponent("资料 folder/中文 文档.txt")).contains("中文测试"), "unicode content")
            check(fileSize(destination.appendingPathComponent("资料 folder/sub/random.bin")) == 16384, "binary size")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("empty").path), "empty directory created")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a b/file name.txt").path), "space path created")
            check(!hasStagingLeftover(destination), "no staging leftover")
            check((progress.first ?? 1) < 0.01, "initial progress is near zero")
            check(progress.last == 1, "final progress is 100% (got \(progress.last ?? -1))")
            check(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 + 0.0001 }, "progress is monotonic")
        } catch {
            check(false, "extract sample threw: \(error)")
        }
    }

    static func testCollisionSafety(_ service: SafeExtractionService) async {
        section("collision safety")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let existing = destination.appendingPathComponent("readme.txt")
        try? "original\n".write(to: existing, atomically: true, encoding: .utf8)

        do {
            let listing = try await serviceListing("sample.rar")
            _ = try await service.extract(
                archive: fixture("sample.rar"),
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            _ = try await service.extract(
                archive: fixture("sample.rar"),
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            check(readText(existing) == "original\n", "existing file is untouched")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("readme 2.txt").path), "first conflict renamed to 2")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("readme 3.txt").path), "second conflict renamed to 3")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("资料 folder/中文 文档 2.txt").path), "nested conflict renamed")
            check(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("资料 folder/中文 文档 3.txt").path), "only one nested conflict rename occurred")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("资料 folder/中文 文档.txt").path), "original nested file is untouched")
            check(!hasStagingLeftover(destination), "no staging leftover after merges")
        } catch {
            check(false, "collision extraction threw: \(error)")
        }
    }

    static func testEncryptedHeaders(_ engine: UnrarEngine, _ service: SafeExtractionService) async {
        section("encrypted headers")
        let archive = fixture("encrypted-headers.rar")
        let password = "s3cret-密码"
        do {
            do {
                _ = try await engine.inspect(archive: archive, password: nil)
                check(false, "listing encrypted headers without a password should fail")
            } catch RARxError.passwordRequired {
                check(true, "password required")
            } catch {
                check(false, "unexpected no-password error: \(error)")
            }

            do {
                _ = try await engine.inspect(archive: archive, password: "wrong")
                check(false, "wrong listing password should fail")
            } catch RARxError.incorrectPassword {
                check(true, "wrong password reported")
            } catch {
                check(false, "unexpected wrong-password error: \(error)")
            }

            let listing = try await engine.inspect(archive: archive, password: password)
            check(listing.encryptedHeaders, "headers flag detected")
            check(listing.requiresPassword, "archive requires password")

            let destination = makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }
            let result = try await service.extract(
                archive: archive,
                listing: listing,
                password: password,
                destination: destination
            ) { _ in }
            check(result.extractedFileCount >= 3, "encrypted files extracted (\(result.extractedFileCount))")
            check(readText(destination.appendingPathComponent("readme.txt")) == "hello RAR\n", "encrypted readme content")
            check(!hasStagingLeftover(destination), "no staging leftover")
        } catch {
            check(false, "encrypted header test threw: \(error)")
        }
    }

    static func testEncryptedData(_ engine: UnrarEngine, _ service: SafeExtractionService) async {
        section("encrypted data")
        let archive = fixture("encrypted.rar")
        let password = "s3cret-密码"
        do {
            let listing = try await engine.inspect(archive: archive, password: nil)
            check(listing.encryptedEntries, "encrypted entry flags detected")
            check(listing.requiresPassword, "requires password")
            check(listing.entries.contains { $0.isEncrypted }, "entry encrypted flag")

            let wrongDestination = makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: wrongDestination) }
            do {
                _ = try await service.extract(
                    archive: archive,
                    listing: listing,
                    password: "wrong",
                    destination: wrongDestination
                ) { _ in }
                check(false, "wrong extraction password should fail")
            } catch RARxError.incorrectPassword {
                check(true, "wrong extraction password reported")
            } catch {
                check(false, "unexpected extraction error: \(error)")
            }
            check(!hasStagingLeftover(wrongDestination), "failed extraction cleans staging")
            check(listing.entries.count > 0, "listing remains available without data password")

            let destination = makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }
            let result = try await service.extract(
                archive: archive,
                listing: listing,
                password: password,
                destination: destination
            ) { _ in }
            check(result.extractedFileCount >= 3, "encrypted archive extracted (\(result.extractedFileCount))")
            check(fileSize(destination.appendingPathComponent("资料 folder/sub/random.bin")) == 16384, "encrypted binary content size")
        } catch {
            check(false, "encrypted data test threw: \(error)")
        }
    }

    static func testSplitVolumes(_ engine: UnrarEngine, _ service: SafeExtractionService) async {
        section("split volumes")
        do {
            let first = try VolumeResolver.firstVolume(for: fixture("split.part2.rar"))
            check(first.lastPathComponent == "split.part1.rar", "part 2 resolves to part 1 (got \(first.lastPathComponent))")
            let listing = try await engine.inspect(archive: first, password: nil)
            check(listing.fileCount == 1, "split archive lists one file")
            check(listing.totalUncompressedSize == 16384, "split archive total size")
            let destination = makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: destination) }
            let result = try await service.extract(
                archive: first,
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            check(result.extractedFileCount == 1, "split file extracted")
            check(fileSize(destination.appendingPathComponent("random.bin")) == 16384, "split file full size")
        } catch {
            check(false, "split volume test threw: \(error)")
        }
    }

    static func testUnsafeLinks(_ service: SafeExtractionService) async {
        section("unsafe links")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        do {
            let listing = try await serviceListing("unsafe-links.rar")
            check(listing.fileCount == 4, "symlink archive file count")
            let result = try await service.extract(
                archive: fixture("unsafe-links.rar"),
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            check(result.warnings.contains { $0.localizedCaseInsensitiveContains("symbolic link") }, "unsafe link warning surfaced")
            let safeLink = destination.appendingPathComponent("safe-relative")
            let target = try? FileManager.default.destinationOfSymbolicLink(atPath: safeLink.path)
            check(target == "target.txt", "safe relative symlink preserved")
            check(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("absolute-escape").path), "absolute escaping link skipped")
            check(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("relative-escape").path), "relative escaping link skipped")
            check(!hasStagingLeftover(destination), "no staging leftover")
        } catch {
            check(false, "unsafe link test threw: \(error)")
        }
    }

    static func testFoldersOnly(_ service: SafeExtractionService) async {
        section("folders only")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        do {
            let listing = try await serviceListing("folders-only.rar")
            let result = try await service.extract(
                archive: fixture("folders-only.rar"),
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            check(result.extractedFileCount == 0, "no regular files")
            var isDir: ObjCBool = false
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("empty").path, isDirectory: &isDir) && isDir.boolValue, "empty directory created")
            check(!hasStagingLeftover(destination), "no staging leftover")
        } catch {
            check(false, "folders-only test threw: \(error)")
        }
    }

    static func testInvalidArchives(_ engine: UnrarEngine) async {
        section("invalid archives")
        do {
            _ = try await engine.inspect(archive: fixture("invalid.rar"), password: nil)
            check(false, "invalid archive should fail")
        } catch RARxError.notARARArchive {
            check(true, "invalid archive rejected")
        } catch {
            check(false, "unexpected invalid archive error: \(error)")
        }

        do {
            _ = try await engine.inspect(archive: fixture("truncated.rar"), password: nil)
            check(false, "truncated archive should fail")
        } catch RARxError.invalidArchive {
            check(true, "truncated archive rejected")
        } catch {
            check(false, "unexpected truncated archive error: \(error)")
        }
    }

    static func testVolumeResolution() {
        section("volume resolution")
        do {
            let resolved = try VolumeResolver.firstVolume(for: fixture("missing-first.part2.rar"))
            check(false, "missing first volume should fail, got \(resolved.lastPathComponent)")
        } catch RARxError.missingVolume {
            check(true, "missing first volume reported")
        } catch {
            check(false, "unexpected missing-volume error: \(error)")
        }
    }

    static func testMissingSecondVolume(_ service: SafeExtractionService) async {
        section("missing second volume")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let partial = destination.appendingPathComponent("split.part1.rar")
        do {
            try FileManager.default.copyItem(at: fixture("split.part1.rar"), to: partial)
            let listing = try await serviceListingForPath(partial)
            do {
                _ = try await service.extract(
                    archive: partial,
                    listing: listing,
                    password: nil,
                    destination: destination
                ) { _ in }
                check(false, "incomplete split archive should fail")
            } catch {
                check(true, "incomplete split archive rejected: \(error.localizedDescription)")
            }
            check(!hasStagingLeftover(destination), "failed split extraction cleans staging")
            check(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("random.bin").path), "no partial file committed")
        } catch {
            check(false, "missing volume test setup failed: \(error)")
        }
    }

    static func testStaleStagingCleanup(_ service: SafeExtractionService) async {
        section("stale staging cleanup")
        let destination = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let stale = destination.appendingPathComponent(".rarx-11111111-1111-1111-1111-111111111111.tmp", isDirectory: true)
        let lock = destination.appendingPathComponent(".rarx-11111111-1111-1111-1111-111111111111.lock")
        do {
            try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
            try "partial".write(to: stale.appendingPathComponent("orphan.txt"), atomically: true, encoding: .utf8)
            try "999999\n".write(to: lock, atomically: true, encoding: .utf8)
            let listing = try await serviceListingForPath(fixture("sample.rar"))
            _ = try await service.extract(
                archive: fixture("sample.rar"),
                listing: listing,
                password: nil,
                destination: destination
            ) { _ in }
            check(!FileManager.default.fileExists(atPath: stale.path), "abandoned staging directory removed")
            check(!FileManager.default.fileExists(atPath: lock.path), "abandoned lock removed")
            check(!hasStagingLeftover(destination), "no staging leftovers after cleanup")
            check(FileManager.default.fileExists(atPath: destination.appendingPathComponent("readme.txt").path), "fresh extraction succeeded")
        } catch {
            check(false, "stale staging cleanup failed: \(error)")
        }
    }

    static func serviceListingForPath(_ url: URL) async throws -> ArchiveListing {
        let engine = UnrarEngine(executableURL: enginePath)
        return try await engine.inspect(archive: url, password: nil)
    }

    static func testNoPasswordInLog(_ path: URL) {
        section("password hygiene")
        AppLog.flush()
        let text = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        check(!text.contains("s3cret-密码"), "password is not written to log")
    }

    // MARK: - Helpers

    static func serviceListing(_ name: String) async throws -> ArchiveListing {
        let engine = UnrarEngine(executableURL: enginePath)
        return try await engine.inspect(archive: fixture(name), password: nil)
    }

    static func fixture(_ name: String) -> URL {
        fixtures.appendingPathComponent(name)
    }

    static func section(_ name: String) {
        print("\n— \(name)")
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if condition() {
            print("  ✓ \(message)")
        } else {
            failures += 1
            print("  ✗ \(message)")
        }
    }

    static func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rarx-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func readText(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return -1 }
        return size.int64Value
    }

    static func hasStagingLeftover(_ destination: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []
        return contents.contains { $0.hasPrefix(".rarx-") }
    }
}
