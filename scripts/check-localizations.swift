import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let sources = root.appendingPathComponent("Sources", isDirectory: true)
let enURL = root.appendingPathComponent("Resources/en.lproj/Localizable.strings")
let zhURL = root.appendingPathComponent("Resources/zh-Hans.lproj/Localizable.strings")

var failures: [String] = []

func fail(_ message: String) {
    failures.append(message)
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
}

func unescapeSwift(_ value: String) -> String {
    var result = ""
    var iterator = value.makeIterator()
    while let character = iterator.next() {
        guard character == "\\", let next = iterator.next() else {
            result.append(character)
            continue
        }
        switch next {
        case "n": result.append("\n")
        case "t": result.append("\t")
        case "\"": result.append("\"")
        case "\\": result.append("\\")
        default: result.append(next)
        }
    }
    return result
}

func sourceKeys() -> Set<String> {
    var keys = Set<String>()
    guard let enumerator = FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        fail("Cannot enumerate Sources")
        return keys
    }
    let expression = try! NSRegularExpression(pattern: #"L\(\s*"((?:\\.|[^"\\])*)""#)
    for case let file as URL in enumerator where file.pathExtension == "swift" {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fail("Cannot read \(file.path)")
            continue
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in expression.matches(in: text, range: range) {
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: text) else { continue }
            keys.insert(unescapeSwift(String(text[valueRange])))
        }
    }
    return keys
}

func loadStrings(_ url: URL) -> [String: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    process.arguments = ["-convert", "json", "-o", "-", url.path]
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    do {
        try process.run()
    } catch {
        fail("Cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        return [:]
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(decoding: errorData, as: UTF8.self)
        fail("plutil failed for \(url.path): \(message)")
        return [:]
    }
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        fail("Cannot parse \(url.path)")
        return [:]
    }
    return object
}

let keys = sourceKeys()
let en = loadStrings(enURL)
let zh = loadStrings(zhURL)

for key in keys where en[key] == nil {
    fail("Missing English key: \(key)")
}
for key in keys where zh[key] == nil {
    fail("Missing Chinese key: \(key)")
}
for key in Set(en.keys).union(zh.keys) where !keys.contains(key) {
    fail("Localization key is not used in Sources: \(key)")
}

let specifierExpression = try! NSRegularExpression(pattern: #"%(@|d|ld|lld|s)"#)
func specifiers(_ value: String) -> [String] {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return specifierExpression.matches(in: value, range: range).compactMap { match in
        guard let subrange = Range(match.range, in: value) else { return nil }
        return String(value[subrange])
    }.sorted()
}

for key in keys {
    guard let english = en[key], let chinese = zh[key] else { continue }
    if specifiers(key) != specifiers(english) {
        fail("English value changed format specifiers: \(key)")
    }
    if specifiers(key) != specifiers(chinese) {
        fail("Chinese value has different format specifiers: \(key)")
    }
}

if failures.isEmpty {
    print("Localization check passed: \(keys.count) keys in English and Simplified Chinese.")
    exit(0)
} else {
    print("Localization check failed with \(failures.count) error(s).")
    exit(1)
}
