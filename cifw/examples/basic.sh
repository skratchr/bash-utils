#!/usr/bin/env bash

set -e

source ../group.bash "base-test"

rc() {
  local return_code="${1:?"Missing value"}"
  return "${return_code}"
}

echo ""
echo "isolated tests"
echo ""

(
  source ../case.bash "isolated-passing"
  echo "start test 1"
  if ! rc 0; then
    $test_failed "test 1 failed"
  fi
)

(
  indent="true"
  source ../case.bash "isolated-passing-indent"
  echo "start test 2"
  if ! rc 0; then
    $test_failed "test 2 failed"
  fi
)

(
  source ../case.bash "isolated-failing"
  if ! rc 1; then
    $test_failed "test 3 failed"
  fi
)

(
  indent="true"
  source ../case.bash "isolated-failing-indent"
  if ! rc 1; then
    $test_failed "test 4 failed"
  fi
)

echo ""
echo "non-isolated tests"
echo ""

log_stderr "* RUN: non-isolated test case passing"
if rc 0; then
  log_stderr "PASS: non-isolated test 1: passed"
  pass
else
  log_stderr "FAIL: non-isolated test 1: failed"
  fail
fi

log_stderr "* RUN: non-isolated test case failing"
if rc 1; then
  log_stderr "PASS: non-isolated test 2: passed"
  pass
else
  log_stderr "FAIL: non-isolated test 2: failed"
  fail
fi
