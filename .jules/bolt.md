## 2025-10-24 - Bash Loop Optimization
**Learning:** Avoid calling `grep` or similar filtering tools (e.g. `cut`) inside a Bash loop over large datasets. This causes an O(N*M) performance bottleneck and forks multiple subprocesses which is slow in Bash.
**Action:** Parse the data once into an associative array for O(1) lookups before the loop instead of searching per iteration.
