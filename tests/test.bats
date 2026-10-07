#!/usr/bin/env bats

# Bats is a testing framework for Bash
# Documentation https://bats-core.readthedocs.io/en/stable/
# Bats libraries documentation https://github.com/ztombol/bats-docs

# For local tests, install bats-core, bats-assert, bats-file, bats-support
# And run this in the add-on root directory:
#   bats ./tests/test.bats
# To exclude release tests:
#   bats ./tests/test.bats --filter-tags '!release'
# For debugging:
#   bats ./tests/test.bats --show-output-of-passing-tests --verbose-run --print-output-on-failure

setup() {
  set -eu -o pipefail

  # Override this variable for your add-on:
  export GITHUB_REPO=CandoImage/ddev-silo

  TEST_BREW_PREFIX="$(brew --prefix 2>/dev/null || true)"
  export BATS_LIB_PATH="${BATS_LIB_PATH}:${TEST_BREW_PREFIX}/lib:/usr/lib/bats"
  bats_load_library bats-assert
  bats_load_library bats-file
  bats_load_library bats-support

  export DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." >/dev/null 2>&1 && pwd)"
  export PROJNAME="test-$(basename "${GITHUB_REPO}")"
  mkdir -p ~/tmp
  export TESTDIR=$(mktemp -d ~/tmp/${PROJNAME}.XXXXXX)
  export DDEV_NONINTERACTIVE=true
  export DDEV_NO_INSTRUMENTATION=true
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1 || true
  cd "${TESTDIR}"
  run ddev config --project-name="${PROJNAME}" --project-tld=ddev.site
  assert_success
  run ddev start -y
  assert_success
}

health_checks() {
  run ddev exec -s silo command -v bash
  assert_success
  assert_output --partial "bash"

  run ddev describe
  assert_success
  assert_output --partial "User: ddevminio"
  assert_output --partial "Pass: ddevminio"
  assert_output --partial "or ddevsilo/ddevsilo"

  # The second console user created by the post-start hook exists and is admin
  run ddev mc admin user info silo ddevsilo
  assert_success
  assert_output --partial "PolicyName: consoleAdmin"

  # Make sure we can hit the 9090 port successfully
  run curl -sfI https://${PROJNAME}.ddev.site:9090
  assert_success
  assert_output --partial "HTTP/2 200"
  assert_output --partial "server: MinIO Console"

  # Both the new "silo" and the legacy "minio" hostnames reach the API
  run ddev exec curl -sf http://silo:10101/minio/health/live
  assert_success
  run ddev exec curl -sf http://minio:10101/minio/health/live
  assert_success

  # Both mc aliases are configured
  run ddev mc ls silo
  assert_success
  run ddev mc ls minio
  assert_success

  # Make sure `ddev silo` and the legacy `ddev minio` work
  DDEV_DEBUG=true run ddev silo
  assert_success
  assert_output --partial "FULLURL https://${PROJNAME}.ddev.site:9090"
  DDEV_DEBUG=true run ddev minio
  assert_success
  assert_output --partial "FULLURL https://${PROJNAME}.ddev.site:9090"
}

teardown() {
  set -eu -o pipefail
  ddev delete -Oy "${PROJNAME}" >/dev/null 2>&1
  # Persist TESTDIR if running inside GitHub Actions. Useful for uploading test result artifacts
  # See example at https://github.com/ddev/github-action-add-on-test#preserving-artifacts
  if [ -n "${GITHUB_ENV:-}" ]; then
    [ -e "${GITHUB_ENV:-}" ] && echo "TESTDIR=${HOME}/tmp/${PROJNAME}" >> "${GITHUB_ENV}"
  else
    [ "${TESTDIR}" != "" ] && rm -rf "${TESTDIR}"
  fi
}

@test "install from directory" {
  set -eu -o pipefail
  echo "# ddev add-on get ${DIR} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${DIR}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}

# bats test_tags=release
@test "install from release" {
  set -eu -o pipefail
  echo "# ddev add-on get ${GITHUB_REPO} with project ${PROJNAME} in $(pwd)" >&3
  run ddev add-on get "${GITHUB_REPO}"
  assert_success
  run ddev restart -y
  assert_success
  health_checks
}
