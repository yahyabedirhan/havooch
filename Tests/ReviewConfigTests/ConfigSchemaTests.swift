import Foundation
import ReviewConfig
import Testing
import TOMLDecoder

// The published schema (`schema/config.schema.json`) is the contract agents
// check their edits against with `taplo check`. These tests check it with a
// small validator that covers the JSON Schema keywords the file uses, after
// Swift Lab's schema tests (yahyabedirhan/swift-lab at ccb82cb,
// `Tests/LabConfigTests/ConfigurationSchemaTests.swift`).

/// This checkout: three folders up from this file.
private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func loadSchema() throws -> [String: Any] {
    let data = try Data(contentsOf: checkout.appendingPathComponent("schema/config.schema.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// A TOML value in the shape JSON Schema sees it.
private indirect enum Value {
    case object([String: Value])
    case array([Value])
    case string(String)
    case integer(Int64)
    case other
}

private func value(of table: TOMLTable) -> Value {
    var object: [String: Value] = [:]
    for key in table.keys {
        if let sub = try? table.table(forKey: key) { object[key] = value(of: sub) }
        else if let array = try? table.array(forKey: key) { object[key] = value(of: array) }
        else if let string = try? table.string(forKey: key) { object[key] = .string(string) }
        else if let integer = try? table.integer(forKey: key) { object[key] = .integer(integer) }
        else { object[key] = .other }
    }
    return .object(object)
}

private func value(of array: TOMLArray) -> Value {
    .array((0..<array.count).map { index in
        if let sub = try? array.table(atIndex: index) { return value(of: sub) }
        if let nested = try? array.array(atIndex: index) { return value(of: nested) }
        if let string = try? array.string(atIndex: index) { return .string(string) }
        if let integer = try? array.integer(atIndex: index) { return .integer(integer) }
        return .other
    })
}

/// The schema violations in `text`, as "path: problem".
private func violations(_ text: String, schema: [String: Any]) throws -> [String] {
    var found: [String] = []
    check(value(of: try TOMLTable(source: text)), against: schema, at: "", into: &found)
    return found
}

private func check(_ value: Value, against schema: [String: Any], at path: String, into found: inout [String]) {
    let type = schema["type"] as? String
    switch value {
    case .object(let object):
        guard type == "object" else { return found.append("\(path): expected \(type ?? "?"), got a table") }
        let properties = schema["properties"] as? [String: Any] ?? [:]
        for key in schema["required"] as? [String] ?? [] where object[key] == nil {
            found.append("\(path): missing \(key)")
        }
        for (key, child) in object {
            if let childSchema = properties[key] as? [String: Any] {
                check(child, against: childSchema, at: path + "." + key, into: &found)
            } else if schema["additionalProperties"] as? Bool == false {
                found.append("\(path): unknown key \(key)")
            }
        }
    case .array(let elements):
        guard type == "array" else { return found.append("\(path): expected \(type ?? "?"), got an array") }
        if let items = schema["items"] as? [String: Any] {
            for (index, element) in elements.enumerated() {
                check(element, against: items, at: "\(path)[\(index)]", into: &found)
            }
        }
    case .string(let string):
        guard type == "string" else { return found.append("\(path): expected \(type ?? "?"), got a string") }
        if let minimum = schema["minLength"] as? Int, string.count < minimum { found.append("\(path): shorter than \(minimum)") }
        if let maximum = schema["maxLength"] as? Int, string.count > maximum { found.append("\(path): longer than \(maximum)") }
        if let pattern = schema["pattern"] as? String, string.range(of: pattern, options: .regularExpression) == nil {
            found.append("\(path): \(string) doesn't match \(pattern)")
        }
    case .integer(let integer):
        guard type == "integer" else { return found.append("\(path): expected \(type ?? "?"), got an integer") }
        if let allowed = schema["enum"] as? [Int], !allowed.contains(Int(integer)) { found.append("\(path): \(integer) not in enum") }
    case .other:
        found.append("\(path): a type the schema has no place for")
    }
}

/// Every property path the schema declares, such as `projects[].slug`.
private func declaredPaths(_ schema: [String: Any], at path: String = "") -> Set<String> {
    var paths: Set<String> = []
    if let properties = schema["properties"] as? [String: Any] {
        for (key, child) in properties {
            let childPath = path.isEmpty ? key : path + "." + key
            paths.insert(childPath)
            paths.formUnion(declaredPaths(child as? [String: Any] ?? [:], at: childPath))
        }
    }
    if let items = schema["items"] as? [String: Any] {
        paths.formUnion(declaredPaths(items, at: path + "[]"))
    }
    return paths
}

/// Every key path set in a TOML value, in the same notation.
private func setPaths(_ value: Value, at path: String = "") -> Set<String> {
    switch value {
    case .object(let object):
        var paths: Set<String> = []
        for (key, child) in object {
            let childPath = path.isEmpty ? key : path + "." + key
            paths.insert(childPath)
            paths.formUnion(setPaths(child, at: childPath))
        }
        return paths
    case .array(let elements):
        return elements.reduce(into: []) { $0.formUnion(setPaths($1, at: path + "[]")) }
    default:
        return []
    }
}

@Suite("The JSON Schema of config.toml")
struct ConfigSchemaTests {
    @Test("the schema declares exactly the keys Havooch reads, and its id is the file's #:schema line")
    func sameKeys() throws {
        let schema = try loadSchema()
        #expect(schema["$id"] as? String == ConfigFile.schemaURL)
        #expect(try ConfigFile.decode(ConfigFileTests.everyKey).warnings == [])
        #expect(declaredPaths(schema) == setPaths(value(of: try TOMLTable(source: ConfigFileTests.everyKey))))
    }

    @Test("a file with every key, and the header, validate against the schema")
    func validates() throws {
        let schema = try loadSchema()
        #expect(try violations(ConfigFileTests.everyKey, schema: schema) == [])
        #expect(try violations(ConfigFile.header, schema: schema) == [])
    }

    @Test("the schema refuses what the reader refuses, and an unknown key")
    func refuses() throws {
        let text = """
            version = 2
            theme = ""
            colour = "red"
            [[projects]]
            slug = "Launch Video"
            versions = [{ path = "cut1.mp4", note = "x" }]
            [[projects]]
            title = "No slug"

            """
        #expect(Set(try violations(text, schema: try loadSchema())) == [
            ": unknown key colour",
            ".projects[0].slug: Launch Video doesn't match ^[a-z0-9]+(-[a-z0-9]+)*$",
            ".projects[0].versions[0]: unknown key note",
            ".projects[0].versions[0].path: cut1.mp4 doesn't match ^(~|~/.*|/.*)$",
            ".projects[1]: missing slug",
            ".theme: shorter than 1",
            ".version: 2 not in enum",
        ])
    }
}
