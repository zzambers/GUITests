function setupRuntimeSpecifics() {
  if [ "${GITHUB_ACTIONS:?}" == "true" ]; then
    configureGitHubActionsSettings
  else
    configureDefaultSettings
  fi
}

function configureGitHubActionsSettings {
# configure paths
export SCRATCH_DISK=$(mktemp -d)
export TESTS_FOLDER="`dirname ${SCRIPT_DIR}`/tests"

# set TTL not to do manual run
export TTL=60
}

function configureDefaultSettings {
  export TESTS_FOLDER='/mnt/shared/testsuites/GUITests'
}
