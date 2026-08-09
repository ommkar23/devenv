#!/usr/bin/env bash
# Behavioral tests for infrastructure/azure/provision.sh. No live Azure calls.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVISIONER="$ROOT_DIR/infrastructure/azure/provision.sh"
FAKE_BIN="$ROOT_DIR/tests/fakes"
FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

assert_log_line() {
  local description="$1"
  shift
  local line

  while IFS= read -r line; do
    local token matched=true
    for token in "$@"; do
      if [[ "$line" != *"$token"* ]]; then
        matched=false
        break
      fi
    done
    [[ "$matched" == true ]] && return 0
  done <"$COMMAND_LOG"

  fail "$description"
}

assert_log_absent() {
  local description="$1"
  local unexpected="$2"

  if grep -Fq -- "$unexpected" "$COMMAND_LOG"; then
    fail "$description"
  fi
}

assert_log_count() {
  local description="$1" expected="$2" token="$3" actual
  actual="$(grep -Fc -- "$token" "$COMMAND_LOG" || true)"
  if [[ "$actual" != "$expected" ]]; then
    fail "$description (expected $expected, found $actual)"
  fi
}

assert_mutations_scoped_to_subscription() {
  local line

  while IFS= read -r line; do
    case "$line" in
      "az group create "*|\
      "az network vnet create "*|\
      "az network vnet subnet create "*|\
      "az network nsg create "*|\
      "az network nsg rule create "*|\
      "az network nsg rule update "*|\
      "az network public-ip create "*|\
      "az network nic create "*|\
      "az vm create "*|\
      "az vm update "*|\
      "az vm identity assign "*|\
      "az keyvault create "*|\
      "az role assignment create "*)
        if [[ "$line" != *"--subscription sub-test"* ]]; then
          fail "mutating Azure call is not scoped to subscription sub-test: $line"
        fi
        ;;
    esac
  done <"$COMMAND_LOG"
}

run_new_environment_case() {
  local test_dir public_key_file output_file status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"
  public_key_file="$test_dir/id_ed25519.pub"
  output_file="$test_dir/output"
  : >"$COMMAND_LOG"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyPublicKey devenv-test' >"$public_key_file"

  if [[ ! -f "$PROVISIONER" ]]; then
    fail "Milestone 1 requires infrastructure/azure/provision.sh"
    return
  fi

  PATH="$FAKE_BIN:$PATH" \
    AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" \
    AZ_TEST_SUBSCRIPTION="sub-test" \
    SUBSCRIPTION_ID="sub-test" \
    SSH_CIDR="203.0.113.10/32" \
    SSH_PUBLIC_KEY_FILE="$public_key_file" \
    KEY_VAULT="devenv-test-vault" \
    bash "$PROVISIONER" >"$output_file" 2>&1
  status=$?

  if ((status != 0)); then
    fail "a valid new environment should provision successfully with the Azure CLI stub (exit $status; output: $(tr '\n' ' ' <"$output_file"))"
    return
  fi

  assert_log_line "validates the requested subscription without changing global Azure CLI state" \
    "az account show" "--subscription sub-test"
  assert_log_absent "does not change global Azure CLI subscription state" \
    "az account set"
  assert_log_line "creates the Central India resource group" \
    "az group create" "--name devenv-rg" "--location centralindia" "--subscription sub-test"
  assert_log_line "creates the virtual network" \
    "az network vnet create" "--resource-group devenv-rg" "--subscription sub-test"
  assert_log_line "restricts SSH to the requested IPv4 CIDR and TCP port 22" \
    "az network nsg rule" "--source-address-prefixes 203.0.113.10/32" "--destination-port-ranges 22" "--protocol Tcp"
  assert_log_line "creates a static Standard IPv4 address" \
    "az network public-ip create" "--allocation-method Static" "--sku Standard" "--version IPv4"
  assert_log_line "creates a 2-vCPU starter VM with managed identity and SSH-only authentication" \
    "az vm create" "--name devenv-01" "--size Standard_D2s_v5" \
    "--image Canonical:ubuntu-24_04-lts:server:latest" "--admin-username op" \
    "--authentication-type ssh" "--assign-identity" "--security-type TrustedLaunch" \
    "--enable-secure-boot true" "--enable-vtpm true" \
    "--os-disk-size-gb 100" "--storage-sku StandardSSD_LRS"
  assert_log_line "installs the selected public key file" \
    "az vm create" "--ssh-key-values $public_key_file"
  assert_log_line "retains the OS disk when the VM is deleted" \
    "az vm update" "storageProfile.osDisk.deleteOption=Detach"
  assert_log_line "creates an RBAC-enabled Key Vault" \
    "az keyvault create" "--name devenv-test-vault" "--enable-rbac-authorization true"
  assert_log_line "grants the VM identity vault-scoped secret read access" \
    "az role assignment create" "--assignee-object-id principal-test" \
    "--role 4633458b-17de-408a-b874-0445c86b69e6" \
    "--scope /subscriptions/sub-test/resourceGroups/devenv-rg/providers/Microsoft.KeyVault/vaults/devenv-test-vault"
  assert_log_line "checks role assignments without an unnecessary Microsoft Graph lookup" \
    "az role assignment list" "--assignee-object-id principal-test" "--fill-principal-name false"
  assert_mutations_scoped_to_subscription
  grep -Fq 'Azure devenv host ready:' "$output_file" || fail "provisioner should print a safe resource summary"
  grep -Fq 'AAAAC3Nza' "$output_file" && fail "summary must not expose SSH key material"
  grep -Eiq '(access[_ -]?token|secret[_ -]?value)' "$output_file" && fail "summary must not expose tokens or secret values"
}

run_invalid_network_case() {
  local variable="$1" value="$2" test_dir key output status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-net.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"; : >"$COMMAND_LOG"
  key="$test_dir/key.pub"; output="$test_dir/output"
  printf '%s\n' 'ssh-ed25519 AAAATestOnlyKey test' >"$key"
  env "$variable=$value" PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" SUBSCRIPTION_ID=sub-test SSH_CIDR=203.0.113.10/32 \
    SSH_PUBLIC_KEY_FILE="$key" KEY_VAULT=devenv-test-vault \
    bash "$PROVISIONER" >"$output" 2>&1
  status=$?
  ((status != 0)) || fail "$variable=$value must be rejected"
  if grep -Eq '^az (group create|network .* (create|update)|vm (create|update)|vm identity assign|keyvault create|role assignment create)' "$COMMAND_LOG"; then
    fail "$variable=$value must fail before any mutation"
  fi
}

run_override_case() {
  local test_dir key output status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-override.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"; : >"$COMMAND_LOG"
  key="$test_dir/key.pub"; output="$test_dir/output"
  printf '%s\n' 'ssh-ed25519 AAAATestOnlyKey test' >"$key"
  PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$COMMAND_LOG" AZ_TEST_STATE="$test_dir/state" \
    SUBSCRIPTION_ID=sub-test LOCATION=westus2 RESOURCE_GROUP=custom-rg VM_NAME=custom-vm \
    VM_SIZE=Standard_D2as_v5 ADMIN_USER=dev BOOT_DISK_GB=128 BOOT_DISK_SKU=Premium_LRS \
    SSH_CIDR=198.51.100.7/32 SSH_PUBLIC_KEY_FILE="$key" KEY_VAULT=devenv-test-vault \
    bash "$PROVISIONER" >"$output" 2>&1
  status=$?
  ((status == 0)) || { fail "valid configuration overrides should succeed"; return; }
  assert_log_line "VM creation should consistently use configuration overrides" \
    "az vm create" "--resource-group custom-rg" "--name custom-vm" "--location westus2" \
    "--size Standard_D2as_v5" "--admin-username dev" "--os-disk-size-gb 128" "--storage-sku Premium_LRS"
}

run_identity_and_drift_case() {
  local mode="$1" test_dir key output status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-existing.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"; : >"$COMMAND_LOG"
  key="$test_dir/key.pub"; output="$test_dir/output"
  printf '%s\n' 'ssh-ed25519 AAAATestOnlyKey test' >"$key"
  extra=(AZ_TEST_EXISTING_VM=1)
  [[ "$mode" != identity ]] || extra+=(AZ_TEST_IDENTITY_MISSING=1)
  [[ "$mode" != size ]] || extra+=(AZ_TEST_VM_SIZE=Standard_D4s_v5)
  [[ "$mode" != disk ]] || extra+=(AZ_TEST_DISK_SIZE=64)
  env "${extra[@]}" PATH="$FAKE_BIN:$PATH" AZ_TEST_LOG="$COMMAND_LOG" AZ_TEST_STATE="$test_dir/state" \
    SUBSCRIPTION_ID=sub-test SSH_CIDR=203.0.113.10/32 SSH_PUBLIC_KEY_FILE="$key" \
    KEY_VAULT=devenv-test-vault RBAC_RETRY_DELAY_SECONDS=0 bash "$PROVISIONER" >"$output" 2>&1
  status=$?
  if [[ "$mode" == identity ]]; then
    ((status == 0)) || fail "missing existing VM identity should be reconciled"
    assert_log_line "missing identity should be assigned" "az vm identity assign" "--name devenv-01"
  else
    ((status != 0)) || fail "existing VM $mode drift should fail"
    assert_log_absent "$mode drift must not replace the VM" "az vm create"
    assert_log_absent "$mode drift must not mutate the VM" "az vm update"
  fi
}

run_invalid_public_key_case() {
  local description="$1" key_contents="$2" test_dir public_key_file output_file status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"
  public_key_file="$test_dir/key.pub"
  output_file="$test_dir/output"
  : >"$COMMAND_LOG"
  printf '%s\n' "$key_contents" >"$public_key_file"

  PATH="$FAKE_BIN:$PATH" \
    AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" \
    SUBSCRIPTION_ID="sub-test" \
    SSH_CIDR="203.0.113.10/32" \
    SSH_PUBLIC_KEY_FILE="$public_key_file" \
    KEY_VAULT="devenv-test-vault" \
    bash "$PROVISIONER" >"$output_file" 2>&1
  status=$?

  ((status != 0)) || fail "$description should be rejected"
  grep -Fq 'exactly one supported OpenSSH public key' "$output_file" ||
    fail "$description should report the public-key validation boundary"
  [[ ! -s "$COMMAND_LOG" ]] || fail "$description should fail before any Azure CLI call"
}

run_lookup_failure_case() {
  local test_dir public_key_file output_file status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"
  public_key_file="$test_dir/id_ed25519.pub"
  output_file="$test_dir/output"
  : >"$COMMAND_LOG"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyPublicKey devenv-test' >"$public_key_file"

  PATH="$FAKE_BIN:$PATH" \
    AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" \
    AZ_TEST_LOOKUP_FAILURE="network vnet show" \
    SUBSCRIPTION_ID="sub-test" \
    SSH_CIDR="203.0.113.10/32" \
    SSH_PUBLIC_KEY_FILE="$public_key_file" \
    KEY_VAULT="devenv-test-vault" \
    bash "$PROVISIONER" >"$output_file" 2>&1
  status=$?

  ((status != 0)) || fail "authorization errors during resource lookup must not be treated as absence"
  grep -Fq 'Azure resource lookup failed' "$output_file" ||
    fail "resource lookup errors should identify the failing boundary"
  grep -Fq 'AuthorizationFailed' "$output_file" ||
    fail "resource lookup errors should retain the Azure diagnostic"
  assert_log_absent "lookup failure must not trigger creation of the resource that could not be inspected" \
    "az network vnet create"
}

run_vm_security_drift_case() {
  local property="$1" value="$2" expected_error="$3" test_dir public_key_file output_file status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"
  public_key_file="$test_dir/id_ed25519.pub"
  output_file="$test_dir/output"
  : >"$COMMAND_LOG"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyPublicKey devenv-test' >"$public_key_file"

  env_args=(AZ_TEST_SECURE_BOOT=true AZ_TEST_VTPM=true)
  if [[ "$property" == "secure-boot" ]]; then
    env_args=(AZ_TEST_SECURE_BOOT="$value" AZ_TEST_VTPM=true)
  else
    env_args=(AZ_TEST_SECURE_BOOT=true AZ_TEST_VTPM="$value")
  fi

  env "${env_args[@]}" \
    PATH="$FAKE_BIN:$PATH" \
    AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" \
    AZ_TEST_EXISTING_VM=1 \
    SUBSCRIPTION_ID="sub-test" \
    SSH_CIDR="203.0.113.10/32" \
    SSH_PUBLIC_KEY_FILE="$public_key_file" \
    KEY_VAULT="devenv-test-vault" \
    bash "$PROVISIONER" >"$output_file" 2>&1
  status=$?

  ((status != 0)) || fail "existing VM $property drift should fail"
  grep -Fq "$expected_error" "$output_file" || fail "existing VM $property drift should be explicit"
  assert_log_absent "existing VM $property drift must not replace the VM" "az vm create"
  assert_log_absent "existing VM $property drift must not mutate the VM" "az vm update"
}

run_role_retry_case() {
  local failures="$1" attempts="$2" expected_status="$3"
  local role_count="${4:-0}" expected_create_attempts="${5:-$attempts}"
  local test_dir public_key_file output_file status
  test_dir="$(mktemp -d "${TMPDIR:-/tmp}/devenv-azure-test.XXXXXX")"
  trap 'rm -rf "$test_dir"' RETURN
  COMMAND_LOG="$test_dir/az.log"
  public_key_file="$test_dir/id_ed25519.pub"
  output_file="$test_dir/output"
  : >"$COMMAND_LOG"
  printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyPublicKey devenv-test' >"$public_key_file"

  PATH="$FAKE_BIN:$PATH" \
    AZ_TEST_LOG="$COMMAND_LOG" \
    AZ_TEST_STATE="$test_dir/state" \
    AZ_TEST_ROLE_CREATE_FAILURES="$failures" \
    AZ_TEST_ROLE_COUNT="$role_count" \
    SUBSCRIPTION_ID="sub-test" \
    SSH_CIDR="203.0.113.10/32" \
    SSH_PUBLIC_KEY_FILE="$public_key_file" \
    KEY_VAULT="devenv-test-vault" \
    RBAC_RETRY_ATTEMPTS="$attempts" \
    RBAC_RETRY_DELAY_SECONDS=0 \
    bash "$PROVISIONER" >"$output_file" 2>&1
  status=$?

  if [[ "$expected_status" == success ]]; then
    ((status == 0)) || fail "transient RBAC failures should succeed within the retry bound"
  else
    ((status != 0)) || fail "persistent RBAC failures should fail at the retry bound"
    grep -Fq "after $attempts attempts" "$output_file" ||
      fail "persistent RBAC failure should report the bounded attempt count"
  fi
  assert_log_count "RBAC role creation must make exactly the configured bounded attempts" \
    "$expected_create_attempts" "az role assignment create"
}

printf 'TEST: Azure provisioner creates a secure default environment\n'
run_new_environment_case

printf 'TEST: Azure provisioner validates network inputs before mutation\n'
run_invalid_network_case VNET_CIDR 10.20.0.0/99
run_invalid_network_case SUBNET_CIDR not-a-cidr
run_invalid_network_case SUBNET_CIDR 10.21.0.0/24

printf 'TEST: Azure provisioner applies overrides and reconciles identity without accepting drift\n'
run_override_case
run_identity_and_drift_case identity
run_identity_and_drift_case size
run_identity_and_drift_case disk

printf 'TEST: Azure provisioner rejects private, unsupported, and multiline SSH key files\n'
run_invalid_public_key_case "a PEM private key" '-----BEGIN OPENSSH PRIVATE KEY-----'
run_invalid_public_key_case "an unsupported SSH key type" 'ssh-dss AAAAB3NzaC1kc3MAAACBATest'
run_invalid_public_key_case "a multiline key file" $'ssh-ed25519 AAAATest first\nssh-ed25519 AAAATest second'

printf 'TEST: Azure provisioner distinguishes lookup errors from absent resources\n'
run_lookup_failure_case

printf 'TEST: Azure provisioner rejects existing VM secure boot and vTPM drift\n'
run_vm_security_drift_case secure-boot false "incompatible secure-boot"
run_vm_security_drift_case vtpm false "incompatible vTPM"

printf 'TEST: Azure provisioner bounds managed-identity role assignment retries\n'
run_role_retry_case 2 3 success
run_role_retry_case 5 2 failure
run_role_retry_case 0 2 success 1 0

if ((FAILURES > 0)); then
  printf '%d test assertion(s) failed\n' "$FAILURES" >&2
  exit 1
fi

printf 'PASS: Azure provisioning tests\n'
