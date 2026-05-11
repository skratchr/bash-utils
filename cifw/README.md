# cifw

`cifw` is a small set of sourceable Bash modules for writing safer CI and integration scripts.

It is not a full test framework and it does not try to replace Bats, ShellSpec, `go test`, pytest, or any other language-specific runner. Instead, it provides a lightweight control layer for ordinary shell scripts that have grown beyond ad-hoc `set -e` usage but do not need a dedicated test framework.

The main goals are:

- keep test and CI scripts as plain Bash
- isolate selected checks in subshells
- make pass/fail/fatal/skip exits explicit
- aggregate results across isolated checks
- keep cleanup and exit behavior predictable
- allow projects to replace individual modules when they need different semantics

The modules are intended to be used together when convenient, but they are not meant to force one fixed execution model.

> Status: experimental / work in progress. The core model is present, but the public contracts, examples, and edge-case behavior are still being hardened.

## What this is

`cifw` is best understood as a small Bash runtime/helper layer for CI scripts.

It gives you optional building blocks:

| Module | Role |
| --- | --- |
| `group.env` | Provides grouped result aggregation and shared pass/fail accounting. |
| `case.env` | Provides one implementation of an isolated case context. |
| `build.env` | Provides optional build/workspace/executor conventions for larger CI flows. |

A project may use all of them, only some of them, or replace one module with a project-specific implementation.

For example:

```bash
source ./group.env "smoke-tests"
```

can be enough if the script wants grouped pass/fail accounting.

```bash
(
  source ./case.env "install-package"
  ./install.sh || $test_failed "install failed"
)
```

adds the default isolated case behavior.

A different project may keep `group.env` but replace `case.env` with another implementation that reports compatible results.

## What this is not

`cifw` is not meant to be:

- a general-purpose shell unit-test framework
- an assertion library
- a test discovery system
- a TAP/JUnit reporting framework
- a replacement for Bats or ShellSpec
- a mandatory DSL for writing tests

The intention is simpler:

> Keep writing normal shell scripts, but source small modules when you want controlled exits, isolation, cleanup, and result aggregation.

## Core model

The default stack looks like this:

```text
build.env        optional CI/build/workspace conventions
  group.env      result aggregation for one logical group
    case.env     optional isolated case wrapper
      shell code ordinary project-specific commands
```

But the modules do not need to be used only in this shape.

The important separation is:

```text
result sink -> optional isolated execution wrapper -> ordinary shell code
```

`group.env` provides the default result sink.

`case.env` is the default isolated execution wrapper.

Your script remains ordinary Bash.

## Minimal grouped usage

You can use `group.env` without isolated cases.

```bash
#!/usr/bin/env bash
set -e

source ./group.env "basic"

if ./health-check.sh; then
  log_stderr "PASS: health check"
  pass
else
  log_stderr "FAIL: health check"
  fail
fi

if ./migration-check.sh; then
  log_stderr "PASS: migration check"
  pass
else
  log_stderr "FAIL: migration check"
  fail
fi
```

This is useful when you want grouped accounting, but do not need a subshell or an automatic case `EXIT` trap.

## Isolated case usage

For checks that should not leak variables, working directories, shell options, or traps into the rest of the script, source `case.env` inside a subshell.

```bash
#!/usr/bin/env bash
set -e

source ./group.env "basic"

(
  source ./case.env "passing-case"

  ./command-that-should-pass || $test_failed "command failed"
)

(
  source ./case.env "failing-case"

  ./command-that-should-fail && $test_failed "command unexpectedly passed"
)
```

The default `case.env` installs an `EXIT` trap for the current subshell. The trap converts the case exit state into a group result.

Use a subshell for each isolated case:

```bash
(
  source ./case.env "case-name"
  # case body
)
```

This keeps the scope of traps, variables, `cd`, and shell options local to that case.

## Non-isolated and isolated checks can be mixed

A group may contain both styles:

```bash
source ./group.env "mixed"

(
  source ./case.env "isolated-check"
  ./setup-and-check.sh || $test_failed "isolated check failed"
)

log_stderr "* RUN: direct check"
if ./direct-check.sh; then
  pass
else
  fail
fi
```

This is intentional. `case.env` is a convenience module, not a requirement for every check.

## Replacing `case.env`

The default `case.env` is only one implementation of an isolated result-producing context.

A project can replace it if it needs different behavior, such as:

- different filtering rules
- different skip semantics
- different artifact behavior
- different fatal handling
- wrapping a language-specific test runner
- executing the body through a container, VM, or remote shell

The replacement should follow the active result protocol expected by the group module.

Conceptually:

```bash
source ./group.env "project-tests"

(
  source ./project_case.env "custom-case"
  run_project_specific_check
)
```

The dependency should remain one-way:

```text
case implementation -> reports result to active group/result sink
group implementation -> aggregates results without caring how they were produced
```

## Result states

The default modules distinguish these states:

| State | Meaning | Expected group behavior |
| --- | --- | --- |
| `PASS` | The check succeeded. | Count as passed and continue. |
| `FAIL` | The check failed in an expected/assertion-like way. | Count as failed and continue. |
| `SKIP` | The check was intentionally skipped. | Report or ignore according to module behavior. |
| `FATAL` | The current script or group cannot continue safely. | Stop the group/build in a controlled way. |

The exact transport is an implementation detail of the active modules. The default implementation uses shell functions, exit codes, traps, and a group result pipe.

## Failure helpers

Inside the default `case.env`, use `$test_failed` for a normal check failure:

```bash
./verify.sh || $test_failed "verification failed"
```

Use `$test_fatal` when the rest of the group should not continue:

```bash
./prepare-required-environment.sh || $test_fatal "required environment setup failed"
```

These helpers include source location information in diagnostic output.

## Filtering, skipping, and listing cases

The default `case.env` supports environment-variable based control.

Skip selected cases:

```bash
SKIP="slow-case flaky-case" ./run-tests.sh
```

Run only selected cases:

```bash
FILTER="specific-case" ./run-tests.sh
```

List cases without running their bodies:

```bash
LIST_CASE=true ./run-tests.sh
```

These controls belong to the default `case.env` implementation. A project-specific replacement may choose different behavior.

## Indented case output

Set `indent=true` before sourcing `case.env` to indent output from the case body.

```bash
(
  indent=true
  source ./case.env "verbose-case"

  echo "this output is indented"
)
```

This can make CI logs easier to read when a case produces verbose output.

## Artifacts

The default modules can write result artifacts under `ARTIFACTS_DIR`.

For example, a group named `network` may append result records to:

```text
${ARTIFACTS_DIR}/network.result
```

A result file may contain lines such as:

```text
case-name,PASS
case-name,FAIL
case-name,SKIP
```

Artifact behavior is intentionally simple and can be replaced or extended by project-specific modules.

## Optional build/workspace layer

`build.env` is an optional higher-level module for scripts that want shared build or execution conventions.

It may provide things such as:

- project root detection
- repository metadata
- workspace paths
- artifact paths
- environment setup
- overridable execution functions
- cleanup registration

The important point is that `build.env` should be treated as a default convention layer, not as the owner of every test flow.

A project can source it and override behavior:

```bash
source ./build.env

run_environment() {
  echo "running directly on host"
}

stop_environment() {
  echo "nothing to stop"
}

do_exec() {
  bash "$@"
}
```

This makes the module useful both for local debugging and for CI environments.

## Example: local host runner

A local runner can reuse the build defaults while replacing execution behavior:

```bash
#!/usr/bin/env bash
set -e

source ./build.env

git_config() {
  echo "configure git private access ignored"
}
export -f git_config

run_environment() {
  echo "run ignored, running on host machine"
}
export -f run_environment

stop_environment() {
  echo "stop ignored, running on host machine"
}
export -f stop_environment

delete_environment() {
  echo "delete environment ignored, running on host machine"
}
export -f delete_environment

do_exec() {
  bash "$@"
}
export -f do_exec

cleanup() {
  echo "cleanup local workspace"
}
export -f cleanup

./run_unit_tests.sh
./run_end_to_end_tests.sh
```

This style keeps the top-level runner project-specific while allowing shared setup and cleanup conventions to live in `build.env`.

## Module contracts

The contracts should stay small so the modules remain replaceable.

### `group.env`

Default responsibility:

- start one named result group
- expose result-reporting helpers such as `pass` and `fail`
- aggregate results from direct checks and isolated subshells
- print a final summary
- return a group-level exit status

It should not require every check to use `case.env`.

### `case.env`

Default responsibility:

- initialize one isolated case in the current subshell
- install case-local traps
- expose `$test_failed` and `$test_fatal`
- convert controlled exits into result records
- optionally indent case output
- report the final case result to the active group/result sink

It should be replaceable by another module with compatible result-reporting behavior.

### `build.env`

Default responsibility:

- provide optional CI/build/workspace conventions
- expose overridable execution and cleanup hooks
- keep project-specific execution details outside the lower-level group/case modules

It should be optional for users who only need `group.env` and `case.env`.

## Current limitations

`cifw` is still experimental. Known areas to improve:

- document the result protocol more explicitly
- harden fatal handling so it always exits in a controlled way
- ensure filtering cannot accidentally report a case as passed without running it
- add self-tests for pass/fail/skip/fatal/filter behavior
- clarify which module variables/functions are public API
- keep `util/` separate from the core module contract until it is ready
- consider renaming `.env` files to `.bash` if they are intended primarily as sourceable code modules

## Design principles

`cifw` should stay:

- small
- sourceable
- composable
- boring
- predictable
- easy to override
- usable from ordinary Bash scripts

The goal is not to create a large framework. The goal is to remove repeated fragile shell plumbing from CI and integration scripts while keeping the scripts understandable.
