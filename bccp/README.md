# bccp (Bash CI/CD Pipeline)

Sourceable bash modules for writing smaller CI pipelines. Suited for platforms
like GitHub Actions where pipelines are shell scripts by nature. It is generally
expected that the modules will require some modification for each project.

This can be done by modifying the files directly or creating extensions
such as the files in `util`, and sourcing them as required. See `utils/`

The `examples` folder includes some basic use-cases.


- `build.env` — sets up the shared build environment: repo metadata, artifact
  paths, and an isolation provider. Can be sourced at the top of a runner script
  or by individual scripts running in separate jobs to ensure a clean environment.

- `group.bash` — source to open a named result group. Aggregates pass/fail from
  direct calls and subshells via a FIFO; writes CSV result records to `$ARTIFACTS_DIR`.

- `case.bash` — sub-module of `group.bash`. Source inside a subshell to get an
  isolated case context with an EXIT trap that reports pass/fail automatically.
  Requires a running group in the parent shell.


