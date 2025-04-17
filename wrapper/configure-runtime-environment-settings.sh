function setupRuntimeSpecifics() {
  if [ "${GITHUB_ACTIONS:?}" == "true" ]; then
    configureGitHubActionsSettings
  else
    configureDefaultSettings
  fi
}

function configureGitHubActionsSettings {
export SCRATCH_DISK=$(mktemp -d)
export TESTS_FOLDER="`dirname ${SCRIPT_DIR}`/tests"
}

function configureDefaultSettings {
  export TESTS_FOLDER='/mnt/shared/testsuites/GUITests'
}
