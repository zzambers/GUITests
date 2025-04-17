function setupRuntimeSpecifics() {
  if [ "${GITHUB_ACTIONS:?}" == "true" ]; then
    configureGitHubActionsSettings
  else
    configureDefaultSettings
  fi
}

function configureGitHubActionsSettings {
# get tested binaries
export WORKSPACE=$(mktemp -d)
export SCRATCH_DISK=$(mktemp -d)

# configure paths
export TESTS_FOLDER="`dirname ${SCRIPT_DIR}`/tests"

# set TTL not to do manual run
export TTL=60
}

function configureDefaultSettings {
  export TESTS_FOLDER='/mnt/shared/testsuites/GUITests'
}
