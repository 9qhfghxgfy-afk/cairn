import Foundation
import Testing
@testable import CairnInferenceLocal

/// The ceiling on the runtime's buffer pool, and the sizes the refusal sentences are written in.
///
/// Both are pinned because both are numbers a person's phone is going to be run at. The ceiling because
/// a pool that is allowed to grow is the memory a jetsam report counts as dirty and unpurgeable; the
/// formatting because a refusal that prints a raw byte count tells the person nothing they can act on.
struct MLXMemoryBudgetTests {
    @Test func theCeilingIsTheNumberTheDeviceBuildsRunAt() {
        // 32 MiB. mlx-swift's own iOS article suggests "up to 20 megabytes of buffer cache" for LLM
        // evaluation; this sits above that for a little headroom and far below the default, which the
        // package documents as the runtime's whole memory limit — 1.5× the recommended working set.
        #expect(MLXMemoryBudget.cacheLimitCeilingBytes == 32 * 1024 * 1024)
        #expect(MLXMemoryBudget.cacheLimitFloorBytes == 8 * 1024 * 1024)
        #expect(MLXMemoryBudget.cacheLimitFloorBytes < MLXMemoryBudget.cacheLimitCeilingBytes)
    }

    @Test func aGenerousReadingNeverBuysMoreThanTheCeiling() {
        // Eight gigabytes of headroom would let the pool grow to a gigabyte on the runtime's own default.
        // It gets the ceiling instead, because the weights are the allocation that matters and the pool
        // is the one that accumulates beside them.
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 8_000_000_000)
                == MLXMemoryBudget.cacheLimitCeilingBytes)
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 384 * 1024 * 1024)
                == MLXMemoryBudget.cacheLimitCeilingBytes)
    }

    @Test func aSqueezedReadingScalesThePoolDownTowardTheFloor() {
        // An eighth of 192 MiB is 24 MiB — inside the ceiling, so the pool really does shrink with the
        // phone rather than being one constant for every device.
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 192 * 1024 * 1024) == 24 * 1024 * 1024)
        // Below the floor the floor holds: zero pool means no buffer is ever reused and every token
        // re-allocates, which is a different kind of bad.
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 48 * 1024 * 1024)
                == MLXMemoryBudget.cacheLimitFloorBytes)
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 1) == MLXMemoryBudget.cacheLimitFloorBytes)
    }

    @Test func unknownHeadroomIsNeverReadAsRoom() {
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: nil) == MLXMemoryBudget.cacheLimitFloorBytes)
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: 0) == MLXMemoryBudget.cacheLimitFloorBytes)
        #expect(MLXMemoryBudget.cacheLimitBytes(headroomBytes: -1) == MLXMemoryBudget.cacheLimitFloorBytes)
    }

    @Test func byteSizesAreReportedInAUnitAPersonReads() {
        #expect(MemoryByteReport.description(32 * 1024 * 1024) == "32 MiB")
        #expect(MemoryByteReport.description(1_536 * 1024 * 1024) == "1.5 GiB")
        #expect(MemoryByteReport.description(1024) == "0 MiB")
        #expect(MemoryByteReport.description(0) == "0 MiB")
        #expect(MemoryByteReport.description(-5) == "0 MiB")
    }
}
