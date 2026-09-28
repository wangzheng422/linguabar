import CoreAudio
import XCTest
@testable import LinguaBar

final class AudioRenderingActivityTests: XCTestCase {
    func testOwnProcessAndDescendantsDoNotCountAsRenderingActivity() {
        let processIDs: [AudioObjectID: pid_t] = [
            10: 100,
            11: 200,
            12: 300
        ]
        let parentIDs: [pid_t: pid_t] = [
            200: 100,
            300: 200
        ]

        let isRendering = AudioRenderingActivity.isRendering(
            [10, 11, 12],
            excluding: [100],
            processID: { processIDs[$0] },
            parentProcessID: { parentIDs[$0] ?? 0 },
            isRunningOutput: { _ in true }
        )

        XCTAssertFalse(isRendering)
    }

    func testUnrelatedRendererStillCounts() {
        let processIDs: [AudioObjectID: pid_t] = [20: 401]
        let parentIDs: [pid_t: pid_t] = [401: 1]

        let isRendering = AudioRenderingActivity.isRendering(
            [20],
            excluding: [100],
            processID: { processIDs[$0] },
            parentProcessID: { parentIDs[$0] ?? 0 },
            isRunningOutput: { $0 == 20 }
        )

        XCTAssertTrue(isRendering)
    }

    func testUnknownProcessIDDoesNotHideRunningOutput() {
        let isRendering = AudioRenderingActivity.isRendering(
            [30],
            excluding: [100],
            processID: { _ in nil },
            parentProcessID: { _ in XCTFail("Unknown PIDs must not be walked"); return 0 },
            isRunningOutput: { $0 == 30 }
        )

        XCTAssertTrue(isRendering)
    }

    func testNewAndRestartedAudioObjectsAreResolvedFromCurrentProcessTree() {
        let roots: Set<pid_t> = [100]
        var processIDs: [AudioObjectID: pid_t] = [:]
        var parentIDs: [pid_t: pid_t] = [:]
        var processLookups = 0

        func isRendering(_ objects: [AudioObjectID]) -> Bool {
            AudioRenderingActivity.isRendering(
                objects,
                excluding: roots,
                processID: {
                    processLookups += 1
                    return processIDs[$0]
                },
                parentProcessID: { parentIDs[$0] ?? 0 },
                isRunningOutput: { _ in true }
            )
        }

        XCTAssertFalse(isRendering([]), "No current audio objects should be treated as rendering")

        processIDs[40] = 200
        parentIDs[200] = 100
        XCTAssertFalse(isRendering([40]), "A lazily appearing child should be excluded")

        processIDs.removeValue(forKey: 40)
        processIDs[41] = 201
        parentIDs[201] = 100
        XCTAssertFalse(isRendering([41]), "A restarted child has a new audio object and PID")

        parentIDs[201] = 1
        XCTAssertTrue(isRendering([41]), "A reparented process should be reconsidered")
        XCTAssertEqual(processLookups, 3, "Each observed audio object should resolve its PID afresh")
    }

    func testEmptyExclusionSetKeepsRenderingCheckIndependentOfProcessAncestry() {
        let isRendering = AudioRenderingActivity.isRendering(
            [50],
            excluding: [],
            processID: { _ in XCTFail("No process lookup is needed without exclusions"); return nil },
            parentProcessID: { _ in XCTFail("No parent lookup is needed without exclusions"); return 0 },
            isRunningOutput: { $0 == 50 }
        )

        XCTAssertTrue(isRendering)
    }

    func testInvalidRootPIDsCannotExcludeOtherProcesses() {
        let isRendering = AudioRenderingActivity.isRendering(
            [60],
            excluding: [0, 1],
            processID: { _ in 2 },
            parentProcessID: { $0 == 2 ? 1 : 0 },
            isRunningOutput: { _ in true }
        )

        XCTAssertTrue(isRendering)
        XCTAssertFalse(
            AudioRenderingActivity.isDescendant(1, of: [1], parentProcessID: { _ in
                XCTFail("PIDs at or below one cannot be matched")
                return 0
            })
        )
    }

    func testCyclicAncestryStopsWithinEightLookups() {
        var parentLookups = 0

        let isRendering = AudioRenderingActivity.isRendering(
            [70],
            excluding: [100],
            processID: { _ in 42 },
            parentProcessID: { pid in
                parentLookups += 1
                return pid == 42 ? 43 : 42
            },
            isRunningOutput: { _ in true }
        )

        XCTAssertTrue(isRendering, "A cycle unrelated to an excluded root must not hide output")
        XCTAssertGreaterThan(parentLookups, 0)
        XCTAssertLessThanOrEqual(parentLookups, 8)
    }

    @available(macOS 14.2, *)
    func testSystemTapRemainsFullCaptureWithNoExcludedProcesses() {
        let identifier = UUID()
        let description = makeTapDescription(processes: nil, identifier: identifier)

        XCTAssertTrue(description.isExclusive)
        XCTAssertFalse(description.isMono)
        XCTAssertEqual(description.processes, [])
        XCTAssertEqual(description.uuid, identifier)
    }

    @available(macOS 14.2, *)
    func testSelectedProcessTapRemainsMonoAndPreservesItsProcessList() {
        let identifier = UUID()
        let processes: [AudioObjectID] = [81, 82]
        let description = makeTapDescription(processes: processes, identifier: identifier)

        XCTAssertTrue(description.isMono)
        XCTAssertEqual(description.processes, processes)
        XCTAssertEqual(description.uuid, identifier)
    }
}
