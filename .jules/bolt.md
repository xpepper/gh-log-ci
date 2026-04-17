## 2023-10-24 - [Avoid grep in loops for O(N*M) lookups]
**Learning:** Using grep/cut to extract specific elements from a dataset string iteratively inside a loop causes an O(N*M) bottleneck, which is particularly severe when parsing a single large bulk-fetched TSV into individual commit segments.
**Action:** Parse dataset strings into associative arrays before the loop. This changes the O(N*M) text search into an O(N) array buildup + O(1) loop iteration lookup, maximizing Bash text processing performance.
