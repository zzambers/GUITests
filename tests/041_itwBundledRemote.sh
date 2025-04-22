#!/bin/bash
set -ex
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

source "$SCRIPT_DIR/testlib.bash"

if ! isRedHatDistro ; then
  echo "$SKIPPED_no_RH"
  exit 0
fi
if [  "$OTOOL_JDK_VERSION" -lt 11 ]  ; then
  echo "$SKIPPED_itw_remote_jdk11"
  exit 0
fi

parseArguments "$@"
processArguments
setup
installIcedTeaWeb_bundled
runRemoteAppFromPath 2>&1| tee "$REPORT_FILE"
assertSigningHeadlessDialogue  2>&1| tee -a "$REPORT_FILE"
