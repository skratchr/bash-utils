# bt (bash test)

A lightweight test runner for bash scripts, loosely modelled after `go test`.

Pairs a library file (`foo.sh`) with a test file (`test_foo.sh`) in the same directory. For each
function `lib::bar` or `_bar` defined in the library, `bt` expects a corresponding `test_bar`
function in the test file. Tests run in isolated subshells so nothing leaks between them. Output
format mirrors Go — `=== RUN`, `--- PASS/FAIL`, timing per test. Compatible with bash >= 3.2
(macOS system bash).

Assertions use a `${report_failed}` hook — a readonly string that expands to a `_report_failed`
call. Source location is derived from the call stack inside `_report_failed` itself:

```bash
# test_foo.sh
test_parse() {
  local got
  got="$(foo::parse "input")"
  [[ "${got}" == "expected" ]] || ${report_failed} "got=${got}"
}
```

## Usage

```bash
# Run tests in a single directory
bt ./lib

# Run tests recursively (mirrors go test ./...)
bt ./...
bt path/to/pkg/...

# Warn about functions with no matching test, and libraries with no test file
bt --debug ./...
```

## Setup

```bash
# Put bt on your PATH
ln -s /path/to/bt ~/.local/bin/bt

# Optional tab completion
source bt-completion.bash   # or drop in /etc/bash_completion.d/bt
```
