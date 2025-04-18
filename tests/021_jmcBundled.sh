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

if [ "x$OTOOL_OS_NAME" = "xf" -a "$OTOOL_OS_VERSION" -ge "35" ] \
|| [ "x$OTOOL_OS_NAME" = "xel" -a "$OTOOL_OS_VERSION" -ge "10" ] ; then
  echo "$SKIPPED_jmc_decom"
  exit 0
fi

preEclipse
parseArguments "$@"
processArguments
setup
installJMC_bundled
runJmcOnPath 2>&1| tee "$REPORT_FILE"
