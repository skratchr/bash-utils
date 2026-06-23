# bash-utils

An assortment of bash/shell utilities and frameworks aimed to make day-to-day
development easy across different projects, and environments. The scripts are
designed to be usable with minimal external dependencies on macOS, they should


While the tools strive to be general usage, they are tailored to fit my personal
workflow, and the type of projects I'm involved with.

### Content

* Scripts
```
tms           # Plugin free tmux session manager
bt            # Go test inspired framework for writing bash unit tests
brew-ss       # Snapshot of installed brew packages for environment replication
```

* Libraries
```
bccp          # Go test inspired framework for writing ci pipelines/tests
conv          # Conversion functions commonly used for parsing stuff
```

## Dependencies

Required:

- Bash newer than macOS system Bash 3.2
- tmux >= 3.2
- Git

Optional:

- bash-completion, for `bt` tab completion
- fzf, for nicer `tms` interactive selection
- Docker, Lima, or Tart, only when using the matching `bccp` isolation provider
