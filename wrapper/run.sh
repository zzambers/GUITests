#!/bin/bash

set -x
set -e
set -o pipefail

## resolve folder of this script, following all symlinks,
## http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SCRIPT_SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  [[ $SCRIPT_SOURCE != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
readonly SCRIPT_DIR="$( cd -P "$( dirname "$SCRIPT_SOURCE" )" && pwd )"

# get runner
rft=`mktemp -d`
git clone https://github.com/rh-openjdk/run-folder-as-tests.git ${rft} 1>&2
ls -l ${rft}  1>&2
echo ${rft}

# detect runtime environment
# true if running in GitHub Actions, false otherwise
export GITHUB_ACTIONS="${GITHUB_ACTIONS:-false}"

source "$SCRIPT_DIR"/configure-runtime-environment-settings.sh
setupRuntimeSpecifics $SCRIPT_DIR

echo $TESTS_FOLDER
echo $BINARY_FOLDER

# run tests
bash $rft/run-folder-as-tests.sh $TESTS_FOLDER $BINARY_FOLDER
# check for failures in GHA
[ "x${GITHUB_ACTIONS}" = "xtrue" ] && grep "rhqa.failed=0" "${WORKSPACE}"/results/results.properties
