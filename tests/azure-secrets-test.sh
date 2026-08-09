#!/usr/bin/env bash
# Focused local tests for Azure bootstrap and Key Vault integrations.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKE_BIN="$ROOT_DIR/tests/fakes"
FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

contains() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail "$description"
}

test_put_secret() {
  local test_dir env_file log output large_file
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-secret.XXXXXX")"
  env_file="$test_dir/test.env"
  large_file="$test_dir/large.env"
  log="$test_dir/az.log"
  output="$test_dir/output"
  printf '%s\n' 'EXAMPLE_API_KEY=test-only-value' >"$env_file"
  : >"$log"

  if [[ ! -f "$ROOT_DIR/infrastructure/azure/put-secret.sh" ]]; then
    fail "Milestone 2 requires infrastructure/azure/put-secret.sh"
  else
    PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$log" AZ_TEST_STATE="$test_dir/state" \
      KEY_VAULT="devenv-test-vault" \
      bash "$ROOT_DIR/infrastructure/azure/put-secret.sh" devenv-env "$env_file" >"$output" 2>&1 ||
      fail "valid env file should upload through Key Vault"
    contains "$log" "az keyvault secret set" "uploader should set a Key Vault secret"
    contains "$log" "--file $env_file" "uploader should pass the env file without reading it into argv"
    contains "$log" "--encoding utf-8" "uploader should declare UTF-8 encoding"
    grep -Fq 'test-only-value' "$output" && fail "uploader output must not expose secret contents"

    : >"$log"
    if PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$log" AZ_TEST_STATE="$test_dir/state" \
      KEY_VAULT="invalid--vault" \
      bash "$ROOT_DIR/infrastructure/azure/put-secret.sh" devenv-env "$env_file" >/dev/null 2>&1; then
      fail "uploader should reject an invalid Key Vault name"
    fi
    [[ ! -s "$log" ]] || fail "invalid Key Vault name should fail before Azure CLI is invoked"

    head -c 25601 /dev/zero | tr '\0' x >"$large_file"
    if PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$log" AZ_TEST_STATE="$test_dir/state" \
      KEY_VAULT="devenv-test-vault" \
      bash "$ROOT_DIR/infrastructure/azure/put-secret.sh" devenv-env "$large_file" >/dev/null 2>&1; then
      fail "uploader should reject files above 25 KiB"
    fi
  fi
  rm -rf "$test_dir"
}

test_load_secret() {
  local test_dir log output secret_file mode runtime_mode
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-load.XXXXXX")"
  mkdir -p "$test_dir/runtime"
  log="$test_dir/az.log"
  output="$test_dir/output"
  : >"$log"

  if [[ ! -f "$ROOT_DIR/scripts/load-azure-secret.sh" ]]; then
    fail "Milestone 2 requires scripts/load-azure-secret.sh"
  else
    PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$log" AZ_TEST_STATE="$test_dir/state" \
      AZ_TEST_SECRET_VALUE="test-only-secret" AZURE_KEY_VAULT="devenv-test-vault" \
      XDG_RUNTIME_DIR="$test_dir/runtime" \
      bash "$ROOT_DIR/scripts/load-azure-secret.sh" devenv-env >"$output" 2>&1 ||
      fail "managed identity should load the latest Key Vault secret"
    secret_file="$test_dir/runtime/devenv/env/devenv-env.env"
    [[ -f "$secret_file" ]] || fail "loader should create the private runtime env file"
    contains "$log" "az login --identity --allow-no-subscriptions" \
      "loader should authenticate with managed identity without requiring an ARM subscription"
    contains "$log" "az keyvault secret download" "loader should download from Key Vault"
    if [[ -f "$secret_file" ]]; then
      mode="$(stat -f '%Lp' "$secret_file" 2>/dev/null || stat -c '%a' "$secret_file")"
      [[ "$mode" == "600" ]] || fail "loaded secret should have mode 600, found $mode"
    fi
    runtime_mode="$(stat -f '%Lp' "$test_dir/runtime/devenv/env" 2>/dev/null || stat -c '%a' "$test_dir/runtime/devenv/env")"
    [[ "$runtime_mode" == "700" ]] || fail "secret runtime directory should have mode 700, found $runtime_mode"
    grep -Fq 'test-only-secret' "$output" && fail "loader output must not expose secret contents"
  fi
  rm -rf "$test_dir"
}

test_load_failures_cleanup() {
  local failure_kind test_dir log output runtime_dir
  for failure_kind in login download; do
    test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-load-fail.XXXXXX")"
    mkdir -p "$test_dir/runtime"
    log="$test_dir/az.log"; output="$test_dir/output"
    runtime_dir="$test_dir/runtime/devenv/env"
    : >"$log"
    args=(AZ_TEST_LOGIN_FAIL=0 AZ_TEST_SECRET_DOWNLOAD_FAIL=0)
    [[ "$failure_kind" != login ]] || args=(AZ_TEST_LOGIN_FAIL=1 AZ_TEST_SECRET_DOWNLOAD_FAIL=0)
    [[ "$failure_kind" != download ]] || args=(AZ_TEST_LOGIN_FAIL=0 AZ_TEST_SECRET_DOWNLOAD_FAIL=1)
    if env "${args[@]}" PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$log" AZ_TEST_STATE="$test_dir/state" \
      AZURE_KEY_VAULT=devenv-test-vault XDG_RUNTIME_DIR="$test_dir/runtime" \
      bash "$ROOT_DIR/scripts/load-azure-secret.sh" devenv-env >"$output" 2>&1; then
      fail "$failure_kind failure should make the loader fail"
    fi
    [[ ! -e "$runtime_dir/devenv-env.env" ]] || fail "$failure_kind failure must not leave a final secret file"
    if [[ -d "$runtime_dir" ]] && find "$runtime_dir" -maxdepth 1 -name '.devenv-env.*' -print -quit | grep -q .; then
      fail "$failure_kind failure must clean up partial secret files"
    fi
    rm -rf "$test_dir"
  done
}

test_bootstrap_wrapper() {
  local test_dir neutral_log az_log
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-wrapper.XXXXXX")"
  neutral_log="$test_dir/neutral.log"; az_log="$test_dir/az.log"
  : >"$neutral_log"; : >"$az_log"
  COMMAND_LOG="$neutral_log" AZ_TEST_LOG="$az_log" AZ_TEST_STATE="$test_dir/state" \
    PATH="$FAKE_BIN:$PATH" NEUTRAL_BOOTSTRAP="$FAKE_BIN/bootstrap-host" INSTALL_AZURE_CLI=0 \
    bash "$ROOT_DIR/infrastructure/azure/bootstrap-host.sh" >/dev/null 2>&1 ||
    fail "Azure wrapper should run with CLI installation disabled"
  [[ "$(grep -Fc neutral-bootstrap "$neutral_log" || true)" == 1 ]] ||
    fail "Azure wrapper should invoke the configured neutral bootstrap exactly once"
  grep -Eq '^apt-get |^curl |^gpg |^tee ' "$neutral_log" &&
    fail "INSTALL_AZURE_CLI=0 should not invoke installation commands"
  rm -rf "$test_dir"
}

test_provider_selection() {
  local test_dir log
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-provider-select.XXXXXX")"
  log="$test_dir/commands.log"
  : >"$log"

  COMMAND_LOG="$log" HERMES_HOME="$test_dir/hermes" \
    GCP_SECRET_LOADER="$FAKE_BIN/load-gcp-secret" \
    AZURE_SECRET_LOADER="$FAKE_BIN/load-azure-secret" \
    DEVENV_AZURE_SECRET=azure-env bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1 ||
    fail "Azure-only bootstrap selection should succeed"
  contains "$log" "azure-loader azure-env" "Azure secret variable should select Azure loader"

  : >"$log"
  COMMAND_LOG="$log" HERMES_HOME="$test_dir/hermes" \
    GCP_SECRET_LOADER="$FAKE_BIN/load-gcp-secret" \
    AZURE_SECRET_LOADER="$FAKE_BIN/load-azure-secret" \
    DEVENV_GCP_SECRET=gcp-env bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1 ||
    fail "GCP-only bootstrap selection should remain supported"
  contains "$log" "gcp-loader gcp-env" "GCP secret variable should still select GCP loader"

  : >"$log"
  if COMMAND_LOG="$log" HERMES_HOME="$test_dir/hermes" \
    GCP_SECRET_LOADER="$FAKE_BIN/load-gcp-secret" \
    AZURE_SECRET_LOADER="$FAKE_BIN/load-azure-secret" \
    DEVENV_GCP_SECRET=gcp-env DEVENV_AZURE_SECRET=azure-env \
    bash "$ROOT_DIR/scripts/bootstrap.sh" >/dev/null 2>&1; then
    fail "bootstrap should reject simultaneous cloud secret providers"
  fi
  [[ ! -s "$log" ]] || fail "provider conflict should fail before invoking either loader"
  rm -rf "$test_dir"
}

printf 'TEST: Azure Key Vault uploader\n'
test_put_secret
printf 'TEST: Azure managed-identity secret loader\n'
test_load_secret
printf 'TEST: Azure loader cleans up login and download failures\n'
test_load_failures_cleanup
printf 'TEST: Azure bootstrap wrapper reuses the neutral bootstrap\n'
test_bootstrap_wrapper
printf 'TEST: bootstrap cloud-provider selection\n'
test_provider_selection

if ((FAILURES > 0)); then
  printf '%d test assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi
printf 'PASS: Azure secret integration tests\n'
