import XCTest
@testable import ClientVersion

/// Runs the shared conformance fixture (cases.json at the repository root).
final class CasesTests: XCTestCase {
    private var cases: [String: Any]!

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cases.json")
        cases = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    }

    private func list(_ key: String) -> [[String: Any]] { cases[key] as! [[String: Any]] }
    private func str(_ v: Any?) -> String? { v as? String }

    func testParse() {
        for c in list("parse") {
            let got = ClientVersion.parse(c["input"] as? String)
            if let e = c["expected"] as? [String: Any] {
                XCTAssertEqual(got, ClientVersion(app: e["app"] as! String, version: e["version"] as! String,
                                                  build: str(e["build"]), platform: e["platform"] as! String), "\(c["input"]!)")
            } else {
                XCTAssertNil(got, "\(c["input"]!)")
            }
        }
    }

    func testCompare() {
        for c in list("compare") {
            let a = c["a"] as! String, b = c["b"] as! String, e = c["expected"] as! Int
            XCTAssertEqual(ClientVersion.compare(a, b), e, "\(a) vs \(b)")
            XCTAssertEqual(ClientVersion.compare(b, a), -e, "\(b) vs \(a)")
        }
    }

    func testEvaluate() {
        for c in list("evaluate") {
            let policy = (c["policy"] as! [[String: Any]]).map {
                PolicyEntry(app: $0["app"] as! String, platform: $0["platform"] as! String, minimum: str($0["minimum"]),
                            recommended: str($0["recommended"]), upgradeURL: str($0["upgradeUrl"]))
            }
            let name = c["name"] as! String
            let e = c["expected"] as! [String: Any]
            let r = ClientVersionPolicy.evaluate(policy, clientVersion: str(c["clientVersion"]), method: c["method"] as! String)
            XCTAssertEqual(r.level.rawValue, e["level"] as! String, name)
            XCTAssertEqual(r.refuse, e["refuse"] as! Bool, name)
            XCTAssertEqual(r.headers, e["headers"] as! [String: String], name)
            if r.refuse { XCTAssertEqual(r.body, e["body"] as? [String: String], name) }
        }
    }

    func testAtLeast() {
        for c in list("atLeast") {
            XCTAssertEqual(ClientVersion.atLeast(ClientVersion.parse(str(c["clientVersion"])), c["version"] as! String),
                           c["expected"] as! Bool, "\(String(describing: c["clientVersion"])) >= \(c["version"]!)")
        }
    }

    func testHeaderValueRoundTrips() {
        let v = ClientVersion(app: "fleshtimer", version: "1.2.0", build: "42", platform: "macos")
        XCTAssertEqual(v.headerValue, "fleshtimer/1.2.0+42 (macos)")
        XCTAssertEqual(ClientVersion.parse(v.headerValue), v)
    }

    func testUpgradeSignalFromResponse() {
        func response(_ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://x")!, statusCode: status, httpVersion: nil, headerFields: headers)!
        }
        XCTAssertEqual(UpgradeSignal.from(response(200, [:])), UpgradeSignal(level: .none))
        XCTAssertEqual(UpgradeSignal.from(response(200, ["X-Client-Upgrade": "recommended", "X-Upgrade-URL": "https://s"])),
                       UpgradeSignal(level: .recommended, upgradeURL: URL(string: "https://s")))
        XCTAssertEqual(UpgradeSignal.from(response(426, [:])), UpgradeSignal(level: .required))
        XCTAssertEqual(UpgradeSignal.from(response(200, ["X-Client-Upgrade": "bogus"])), UpgradeSignal(level: .none))
    }
}
