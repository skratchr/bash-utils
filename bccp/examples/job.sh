set -e

# An individual job making use of group/case type tests
cd "$(dirname "${BASH_SOURCE[0]}")" && cd "$(git rev-parse --show-toplevel)" || exit 1
export ARTIFACTS_DIR="/path/to/artifacts"

source ../build.env

cp "../group.bash" "${test_workspace}"
cp "../case.bash" "${test_workspace}"

cat <<EOF >>"${test_workspace}/job.sh"
export ARTIFACTS_DIR="${ARTIFACTS_DIR}"
readonly ARTIFACTS_DIR

source "${test_workspace}/group.bash" "test-feature"

( source "${test_workspace}/case.bash" "case-1" ; echo "Passing test" )

( source "${test_workspace}/case.bash" "case-2" ; \$test_failed "Failing test" )

( source "${test_workspace}/case.bash" "case-3" ; echo "Passing test" )
EOF

provider_run
provider_exec "${test_workspace}/job.sh"
provider_remove
