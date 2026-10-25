#!/usr/bin/env bash
# Runs a test and writes its test.xml when the test did not, using bash
# builtins only. actiond's VM has bash and nothing else, so Bazel's own
# fallback (tools/test/generate-xml.sh, which needs cat and sed) cannot run
# there. Used as --run_under by --config=actiond.
status=0
"$@" || status=$?
if [[ -n "${XML_OUTPUT_FILE:-}" && ! -e "$XML_OUTPUT_FILE" ]]; then
  name="${TEST_TARGET:-test}"
  failure=""
  if [[ "$status" != 0 ]]; then
    failure="<failure message=\"exited with $status\"></failure>"
  fi
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites><testsuite name="%s" tests="1" failures="%d" errors="0"><testcase name="%s" status="run">%s</testcase></testsuite></testsuites>\n' \
    "$name" "$((status != 0))" "$name" "$failure" > "$XML_OUTPUT_FILE" || true
fi
exit "$status"
