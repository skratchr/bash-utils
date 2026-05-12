#!/usr/bin/env bash

# A basic ci pipeline, does not use groups/cases directly (these may still be
# used by the executing scripts)

set -e

cd "$(dirname "${BASH_SOURCE[0]}")" && cd "$(git rev-parse --show-toplevel)" || exit 1
export ARTIFACTS_DIR="/Volumes/EXT1/ci-artifacts"

source build.env

echo "Running unit tests"
# ./unit-test.sh

echo "Creating package"
# ./build-pkg.sh

echo "Start test environment"
provider_run
provider_exec <<EOF
echo "Install application"
# ./install-pkg
EOF

echo "Run test environment"
provider_exec <<EOF
echo "Run acceptance test"
# ./acceptance-test.sh
EOF
provider_remove
