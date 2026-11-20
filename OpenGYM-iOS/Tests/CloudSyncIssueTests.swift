import CloudKit
import XCTest
@testable import OpenGYM

final class CloudSyncIssueTests: XCTestCase {
    private func ckError(_ code: CKError.Code, server: String? = nil, items: [CKRecord.ID: Error]? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let server { info["ServerErrorDescription"] = server; info[NSLocalizedDescriptionKey] = server }
        if let items { info[CKPartialErrorsByItemIDKey] = items }
        return NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: info)
    }

    private func id(_ name: String) -> CKRecord.ID { CKRecord.ID(recordName: name) }

    func testPartialFailureFromMissingProductionSchemaNeedsDeployment() {
        let schema = ckError(.invalidArguments, server: "Cannot create new type CD_StoredWorkout in production schema")
        let error = ckError(.partialFailure, items: [
            id("a"): schema, id("b"): schema,
            id("c"): ckError(.batchRequestFailed),
        ])
        let issue = CloudSyncIssue(error: error, phase: .upload)
        XCTAssertEqual(issue.phase, .upload)
        XCTAssertEqual(issue.causes, [CloudSyncIssue.Cause(reason: .schemaNotDeployed, records: 2)])
        XCTAssertTrue(issue.needsAction)
        XCTAssertEqual(issue.details.count, 1)
        XCTAssertTrue(issue.details[0].contains("production schema"), issue.details[0])
    }

    func testCausesAreSortedByRecordCountAndOnlyTransientOnesNeedNoAction() {
        let error = ckError(.partialFailure, items: [
            id("a"): ckError(.serverRecordChanged), id("b"): ckError(.serverRecordChanged),
            id("c"): ckError(.zoneBusy),
        ])
        let issue = CloudSyncIssue(error: error, phase: .upload)
        XCTAssertEqual(issue.causes.map(\.reason), [.conflict, .busy])
        XCTAssertEqual(issue.causes.map(\.records), [2, 1])
        XCTAssertFalse(issue.needsAction)
    }

    func testOnlyBatchFailuresAreStillReported() {
        let error = ckError(.partialFailure, items: [id("a"): ckError(.batchRequestFailed)])
        XCTAssertEqual(CloudSyncIssue(error: error, phase: .upload).causes, [CloudSyncIssue.Cause(reason: .other, records: 1)])
    }

    func testSingleErrorsAndWrappedErrors() {
        XCTAssertEqual(CloudSyncIssue(error: ckError(.quotaExceeded), phase: .upload).causes,
                       [CloudSyncIssue.Cause(reason: .quotaExceeded, records: nil)])
        XCTAssertEqual(CloudSyncIssue(error: ckError(.notAuthenticated), phase: .setup).causes.map(\.reason), [.notSignedIn])
        XCTAssertEqual(CloudSyncIssue(error: URLError(.notConnectedToInternet), phase: .download).causes.map(\.reason), [.network])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [NSUnderlyingErrorKey: ckError(.userDeletedZone)])
        XCTAssertEqual(CloudSyncIssue(error: wrapped, phase: .download).causes.map(\.reason), [.dataDeleted])
        XCTAssertEqual(CloudSyncIssue(error: ckError(.invalidArguments, server: "Bad request"), phase: .upload).causes.map(\.reason), [.other])
    }

    func testEveryReasonHasTextInBothLanguages() {
        let keys = ["CLOUD_SYNC_REASON_SCHEMA", "CLOUD_SYNC_REASON_CONFLICT", "CLOUD_SYNC_REASON_QUOTA", "CLOUD_SYNC_REASON_SIGNED_OUT",
                    "CLOUD_SYNC_REASON_NETWORK", "CLOUD_SYNC_REASON_BUSY", "CLOUD_SYNC_REASON_DELETED", "CLOUD_SYNC_REASON_CONFIGURATION",
                    "CLOUD_SYNC_REASON_OTHER", "CLOUD_SYNC_SETUP_FAILED", "CLOUD_SYNC_DOWNLOAD_FAILED", "CLOUD_SYNC_UPLOAD_FAILED", "ERROR_DETAILS"]
        for language in ["en", "zh"] {
            let bundle = AppLanguage.bundle(for: language), locale = AppLanguage.locale(for: language)
            for key in keys {
                XCTAssertNotEqual(String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale), key, "\(language) \(key)")
            }
        }
    }
}
