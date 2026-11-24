# Blockers

Resolved: P4's TSan warning came from `RingBufferTests.spscStress` polling `Thread.isFinished` before reading the consumer-owned `received` array. The authorized synchronization-only fix uses a `DispatchSemaphore` signaled after the consumer's final append; the test waits before assertions. Assertions, five repetitions, chunk sizes, and ring capacity are unchanged. Three full TSan runs and the normal Capture suite now pass.
