# tree-sitter error recovery loop reproduction

With the 9-rule grammar in `grammar.js`, error recovery on the 14-byte input `<<a/a>{[:aaaaa` repeats the same steps
about 3.5 million times. The parse takes about 16 seconds and 2 GB of memory, and the resulting tree has 7,040,927
zero-width `MISSING "!"` nodes at byte 8. Without the last `a`, the parse finishes in 0.1 ms.

## Reproduce

```sh
npm install
npm run repro
```

`repro.sh` parses both inputs with `tree-sitter parse --time` and a 5-second timeout:

```
.tmp/short.txt	Parse:    0.09 ms	   142 bytes/ms	(ERROR [0, 0] - [0, 13])
.tmp/input.txt	Parse: 5000.01 ms	(timed out)
BUG: parsing the 14-byte input did not finish within 5 seconds.
```

Without the timeout, `tree-sitter parse .tmp/input.txt -q` takes 15.7 s with a peak RSS of 2.0 GB (macOS, Apple
silicon). This reproduces with tree-sitter-cli 0.27.0 and when the grammar is built against `lib/` at tree-sitter
`master` (dcdc8cc5).

## What the debug log shows

After the first few hundred lines, `tree-sitter parse --debug` repeats the same 70-line cycle until the parse ends
(246,432,643 lines in total). One cycle, without the `lex_internal` lines:

```
resume version:0
recover_to_previous state:36, depth:4
condense
process version:1, version_count:3, state:24, row:0, col:8
lexed_lookahead sym::, size:1
reduce sym:expression, child_count:1
detect_error lookahead::
process version:2, version_count:3, state:36, row:0, col:8
shift state:19
process version:2, version_count:3, state:19, row:0, col:9
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
resume version:0
recover_to_previous state:36, depth:4
skip_token symbol::
condense
process version:0, version_count:3, state:0, row:0, col:9
recover_to_previous state:21, depth:7
skip_token symbol:type_token1
process version:0, version_count:4, state:0, row:0, col:10
lexed_lookahead sym:type_token1, size:1
recover_to_previous state:21, depth:7
skip_token symbol:type_token1
process version:0, version_count:5, state:0, row:0, col:11
lexed_lookahead sym:type_token1, size:1
recover_to_previous state:21, depth:7
skip_token symbol:type_token1
process version:0, version_count:6, state:0, row:0, col:12
lexed_lookahead sym:type_token1, size:1
recover_to_previous state:21, depth:7
process version:1, version_count:7, state:24, row:0, col:8
lexed_lookahead sym::, size:1
reduce sym:expression, child_count:1
detect_error lookahead::
process version:2, version_count:7, state:36, row:0, col:8
shift state:19
process version:2, version_count:7, state:19, row:0, col:9
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
process version:3, version_count:7, state:21, row:0, col:9
shift state:41
process version:3, version_count:7, state:41, row:0, col:10
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
process version:4, version_count:7, state:21, row:0, col:10
shift state:41
process version:4, version_count:7, state:41, row:0, col:11
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
process version:5, version_count:7, state:21, row:0, col:11
shift state:41
process version:5, version_count:7, state:41, row:0, col:12
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
process version:6, version_count:7, state:21, row:0, col:12
shift state:41
process version:6, version_count:7, state:41, row:0, col:13
lexed_lookahead sym:type_token1, size:1
detect_error lookahead:type_token1
```

In each cycle, recovery creates versions that reach columns 9 to 13, and every version then pauses on an error.
`ts_parser__condense_stack` resumes the paused version that sorts first, which sits at column 8, and removes the
other paused versions, including those that got further. The resumed version recovers along the same path, so the
next cycle is identical.

The cycles are not free: memory grows by about 130 MB/s, and the final tree has about two zero-width `MISSING "!"` nodes
per cycle, all at byte 8. The debug log never prints `recover_with_missing`, so these tokens seem to reach the tree
without passing the logged branch of `ts_parser__handle_error`.

## Why it ends at all

A missing token costs `ERROR_COST_PER_MISSING_TREE + ERROR_COST_PER_RECOVERY` = 610. For 7,040,927 of them, that is
4,294,965,470, just below 2^32 (4,294,967,296). So the loop seems to end only because the 32-bit error cost would
otherwise overflow, not because recovery makes progress. With a larger grammar, where each cycle does more work, the
same loop effectively never ends: for a real-world grammar, a 15-byte fuzzer input kept allocating memory (about
20 MB/s) and had not finished after 6 minutes.
