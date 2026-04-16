## 2025-10-23 - Avoid grep in loops for O(N*M) performance penalty
**Learning:** Calling `grep` or similar process-spawning filtering tools inside loops over large datasets creates a significant O(N*M) performance penalty, especially in single-threaded bash scripts processing TSV or API outputs.
**Action:** Parse data once outside the loop into an associative array for O(1) lookups instead.
