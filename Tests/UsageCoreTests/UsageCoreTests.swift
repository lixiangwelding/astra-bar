import XCTest
import Foundation
@testable import UsageCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
final class UsageCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1789992000)
    func data(_ v: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: v) }
    func win(_ used: Any = 34, _ mins: Int = 10080, _ reset: Double = 1790500000) -> [String: Any] { ["usedPercent": used, "windowDurationMins": mins, "resetsAt": reset] }
    func bucket(_ id: String = "codex", _ used: Any = 34) -> [String: Any] { ["limitId": id, "planType": "pro", "primary": win(used,300), "secondary": win(used)] }
    func parse(_ v: [String: Any]) throws -> UsageSnapshot { try UsageParser.live(data(v), at: now) }
    func log(_ id: String = "codex", _ used: Int = 34, _ date: Date? = nil) throws -> Data {
        try data(["timestamp": ISO8601DateFormatter().string(from: date ?? now), "type": "event_msg", "payload": ["type": "token_count", "rate_limits": ["limit_id": id, "plan_type": "pro", "primary": ["used_percent": used, "window_minutes":10080,"resets_at":1790500000]]]])
    }
    func dir() throws -> URL {
        let p = FileManager.default.temporaryDirectory.appendingPathComponent("astra-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:p,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:p) }; return p
    }
    func put(_ bytes: Data, _ directory: URL, _ name: String = "test.jsonl", newline: Bool = true) throws -> URL {
        let p=directory.appendingPathComponent(name);var b=bytes;if newline { b.append(10) };try b.write(to:p);return p
    }
    func testWeekMayBeSecondary() throws { let b=try XCTUnwrap(parse(["rateLimits":bucket()]).selected());XCTAssertEqual(b.preferredWindow?.minutes,10080);XCTAssertEqual(b.preferredWindow?.remainingPercent,66) }
    func testWeekMayBePrimary() throws { let s=try parse(["rateLimits":["limitId":"codex","primary":win(88)]]);XCTAssertEqual(s.selected()?.preferredWindow?.label,"每周额度");XCTAssertEqual(StatusText.title(bucket:s.selected(),now:now),"Codex 12%") }
    func testShortWindowIsNotWeekly() throws { let s=try parse(["rateLimits":["limitId":"codex","primary":win(1,300)]]);XCTAssertEqual(s.selected()?.preferredWindow?.label,"5 小时额度");XCTAssertFalse(try XCTUnwrap(s.selected()?.preferredWindow).isWeekly) }
    func testMultipleBucketsStaySeparate() throws { let s=try parse(["rateLimitsByLimitId":["codex":bucket(),"astra":bucket("astra",99)]]);XCTAssertEqual(s.buckets.count,2);XCTAssertEqual(s.selected()?.id,"astra");XCTAssertEqual(s.selected()?.preferredWindow?.remainingPercent,1);XCTAssertEqual(s.selected(preferredID:"codex")?.preferredWindow?.remainingPercent,66) }
    func testReserveAndSparkAreNotAstra() throws { let s=try parse(["rateLimitsByLimitId":["codex":bucket(),"gpt-reserve":bucket("gpt-reserve"),"codex_bengalfox":bucket("codex_bengalfox")]]);XCTAssertFalse(s.hasAstra);XCTAssertEqual(s.selected()?.id,"codex") }
    func testNameCanIdentifyAstra() throws { var b=bucket("model_1");b["limitName"]="GPT-6 Astra";XCTAssertTrue(try parse(["rateLimits":b]).hasAstra) }
    func testMapOverridesDuplicateLegacy() throws { let s=try parse(["rateLimits":bucket("codex",99),"rateLimitsByLimitId":["codex":bucket("codex",20)]]);XCTAssertEqual(s.buckets.count,1);XCTAssertEqual(s.selected()?.preferredWindow?.remainingPercent,80) }
    func testMapKeyFallback() throws { XCTAssertEqual(try parse(["rateLimitsByLimitId":["codex":["primary":win()]]]).selected()?.id,"codex") }
    func testMissingIdentityUnknown() throws { let s=try parse(["rateLimits":["primary":win()]]);XCTAssertEqual(s.selected()?.id,"unknown");XCTAssertFalse(s.hasAstra) }
    func testMissingQuotaNot100() { for v: [String:Any] in [[:],["rateLimits":NSNull()],["rateLimits":["primary":["resetsAt":1790500000]]]] { XCTAssertThrowsError(try parse(v)) } }
    func testInvalidNumbersRejected() { for x:Any in [true,false,"12",-1,Double.nan,Double.infinity] { XCTAssertNil(UsageParser.window(win(x),slot:"p")) } }
    func testOverageClamped() { XCTAssertEqual(UsageParser.window(win(112),slot:"p")?.remainingPercent,0) }
    func testZeroUsageValid() { XCTAssertEqual(UsageParser.window(win(0),slot:"p")?.remainingPercent,100) }
    func testFractionFloored() throws { let s=try parse(["rateLimits":bucket("codex",99.6)]);XCTAssertEqual(StatusText.title(bucket:s.selected(),now:now),"Codex 0%") }
    func testUnknownDuration() { let w=UsageParser.window(["usedPercent":10],slot:"p");XCTAssertEqual(w?.label,"周期未知");XCTAssertNil(w?.resetsAt) }
    func testResetUnitsSeconds() { XCTAssertEqual(UsageParser.window(win(),slot:"p")?.resetsAt?.timeIntervalSince1970,1790500000);XCTAssertNil(UsageParser.window(win(34,10080,1790500000000),slot:"p")?.resetsAt) }
    func testExpiredNeverInventsReset() throws { let s=try parse(["rateLimits":["limitId":"codex","primary":win(95,10080,now.timeIntervalSince1970-1)]]);XCTAssertEqual(StatusText.title(bucket:s.selected(),now:now),"Codex —");XCTAssertEqual(s.selected()?.preferredWindow?.remainingPercent,5) }
    func testStaleAndFailedLosePercent() throws { let b=try XCTUnwrap(parse(["rateLimits":bucket()]).selected());XCTAssertEqual(StatusText.title(bucket:b,now:now.addingTimeInterval(601)),"Codex —");XCTAssertEqual(StatusText.title(bucket:b,failed:true,now:now),"Codex —") }
    func testLogSnapshotMarker() throws { let b=try parse(["rateLimits":bucket()]).selected();XCTAssertEqual(StatusText.title(bucket:b,source:.localLogs,now:now),"Codex ~66%") }
    func testSnakeCaseTimestamp() throws { let b=try XCTUnwrap(UsageParser.logLine(log(),now:now));XCTAssertEqual(b.id,"codex");XCTAssertEqual(b.observedAt,now);XCTAssertEqual(b.preferredWindow?.minutes,10080) }
    func testFutureLogRejected() throws { XCTAssertNil(UsageParser.logLine(try log("codex",34,now.addingTimeInterval(10000)),now:now)) }
    func testNonEventAndCorruptionIgnored() throws { XCTAssertNil(UsageParser.logLine(Data("{broken".utf8),now:now));XCTAssertNil(UsageParser.logLine(try data(["type":"user_message","rate_limits":bucket()]),now:now)) }
    func testEventTimeWinsOverFileTime() throws {
        let d=try dir(),a=try put(log("codex",60),d,"a.jsonl")
        try FileManager.default.setAttributes([.modificationDate:now.addingTimeInterval(-999)],ofItemAtPath:a.path)
        _=try put(log("codex",20,now.addingTimeInterval(-60)),d,"b.jsonl")
        let s=try LogReader.read(directory:d,now:now);XCTAssertEqual(s.selected()?.preferredWindow?.usedPercent,60);XCTAssertEqual(s.source,.localLogs);XCTAssertTrue(s.warnings.joined().contains("其他账号"))
    }
    func testLatestPerBucket() throws { let d=try dir();var b=try log("codex",21);b.append(10);b.append(try log("codex_bengalfox",0));_=try put(b,d);let s=try LogReader.read(directory:d,now:now);XCTAssertEqual(s.buckets.count,2);XCTAssertEqual(s.selected()?.preferredWindow?.usedPercent,21) }
    func testPartialLineIgnored() throws { let d=try dir();_=try put(log(),d,newline:false);XCTAssertThrowsError(try LogReader.read(directory:d,now:now)) }
    func testBoundedTailWarning() throws { let d=try dir();var b=Data(repeating:120,count:2000);b.append(10);b.append(try log());_=try put(b,d);let s=try LogReader.read(directory:d,now:now,tailBytes:512);XCTAssertEqual(s.selected()?.preferredWindow?.usedPercent,34);XCTAssertTrue(s.warnings.joined().contains("有界")) }
    func testSymlinkIgnored() throws { let a=try dir(),b=try dir(),target=try put(log(),a);try FileManager.default.createSymbolicLink(at:b.appendingPathComponent("link.jsonl"),withDestinationURL:target);XCTAssertThrowsError(try LogReader.read(directory:b,now:now)) }
    func testMissingDirectory() { XCTAssertThrowsError(try LogReader.read(directory:URL(fileURLWithPath:"/nonexistent/astra-tests"))) }
    func testNoCredentialsOrPromptsRetained() throws { var b=bucket();b["access_token"]="PRIVATE_SECRET";b["email"]="private@example.test";b["prompt"]="PRIVATE_PROMPT";let out=String(decoding:try JSONEncoder().encode(parse(["rateLimits":b])),as:UTF8.self);XCTAssertFalse(out.contains("PRIVATE"));XCTAssertFalse(out.contains("email"));XCTAssertFalse(out.contains("access_token")) }
    func fake(_ body:String) throws -> URL { let p=try dir().appendingPathComponent("fake codex");try ("#!/bin/sh\n"+body).write(to:p,atomically:true,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:p.path);return p }
    func testRPCHandshakeReadOnly() throws {
        signal(SIGPIPE,SIG_IGN)
        let response=String(decoding:try data(["id":2,"result":["rateLimits":bucket()]]),as:UTF8.self)
        let cli=try fake("""
        IFS= read -r first
        case "$first" in *'"method":"initialize"'*) ;; *) exit 3 ;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r second
        case "$second" in *'"method":"initialized"'*) ;; *) exit 4 ;; esac
        IFS= read -r third
        case "$third" in *'"method":"account/rateLimits/read"'*) ;; *) exit 5 ;; esac
        printf '%s\\n' '\(response)'
        """)
        XCTAssertEqual(try CodexClient.fetch(executable:cli,timeout:2).selected()?.id,"codex")
    }
    func testRPCTimeoutBounded() throws { let c=try fake("exec sleep 5\n"),start=Date();XCTAssertThrowsError(try CodexClient.fetch(executable:c,timeout:0.1));XCTAssertLessThan(Date().timeIntervalSince(start),2) }
    func testRPCErrorSanitized() throws { signal(SIGPIPE,SIG_IGN);let c=try fake("IFS= read -r first\nprintf '%s\\n' '{\"id\":1,\"error\":{\"message\":\"PRIVATE_SECRET\"}}'\n");XCTAssertThrowsError(try CodexClient.fetch(executable:c,timeout:1)) { XCTAssertFalse($0.localizedDescription.contains("PRIVATE_SECRET")) } }
    func testRPCEOFNotQuota() throws { signal(SIGPIPE,SIG_IGN);XCTAssertThrowsError(try CodexClient.fetch(executable:fake("exit 0\n"),timeout:1)) }
    func testRPCRefusesServerRequests() throws { signal(SIGPIPE,SIG_IGN);let c=try fake("IFS= read -r first\nprintf '%s\\n' '{\"id\":99,\"method\":\"account/chatgptAuthTokens/refresh\"}'\n");XCTAssertThrowsError(try CodexClient.fetch(executable:c,timeout:1)) }
    func testBadCLINoFallback() { XCTAssertNil(CodexClient.executable(custom:"/nonexistent/codex")) }
}
