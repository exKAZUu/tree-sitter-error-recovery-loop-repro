#!/bin/sh
# Parses a 13-byte input and a 14-byte input that differ only in one trailing `a`. The first finishes at once; the
# second repeats the same error recovery for about 15 seconds, so it hits the 5-second timeout.
set -eu
cd "$(dirname "$0")"
npx tree-sitter generate
mkdir -p .tmp
printf '<<a/a>{[:aaaa' > .tmp/short.txt
printf '<<a/a>{[:aaaaa' > .tmp/input.txt
npx tree-sitter parse .tmp/short.txt -q --time 2> /dev/null || true
output=$(npx tree-sitter parse .tmp/input.txt -q --time --timeout 5000000 2> /dev/null || true)
echo "$output"
case $output in
  *'timed out'*)
    echo 'BUG: parsing the 14-byte input did not finish within 5 seconds.'
    exit 1
    ;;
  *) echo 'OK: parsing the 14-byte input finished within 5 seconds.' ;;
esac
