#!/usr/bin/env bash
# Idempotently provision the Azure host for the devenv workspace.
set -euo pipefail

LOCATION="${LOCATION:-centralindia}"
RESOURCE_GROUP="${RESOURCE_GROUP:-devenv-rg}"
VM_NAME="${VM_NAME:-devenv-01}"
VM_SIZE="${VM_SIZE:-Standard_D2s_v5}"
ADMIN_USER="${ADMIN_USER:-op}"
BOOT_DISK_GB="${BOOT_DISK_GB:-100}"
BOOT_DISK_SKU="${BOOT_DISK_SKU:-StandardSSD_LRS}"
SSH_CIDR="${SSH_CIDR:-}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_rsa.pub}"
KEY_VAULT="${KEY_VAULT:-}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"

VNET_NAME="${VNET_NAME:-devenv-vnet}"
VNET_CIDR="${VNET_CIDR:-10.20.0.0/16}"
SUBNET_NAME="${SUBNET_NAME:-devenv-subnet}"
SUBNET_CIDR="${SUBNET_CIDR:-10.20.0.0/24}"
NSG_NAME="${NSG_NAME:-devenv-nsg}"
NSG_RULE_NAME="${NSG_RULE_NAME:-AllowSSHFromCIDR}"
PUBLIC_IP_NAME="${PUBLIC_IP_NAME:-devenv-ip}"
NIC_NAME="${NIC_NAME:-devenv-nic}"
IMAGE="${IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"

SECRETS_USER_ROLE_ID="4633458b-17de-408a-b874-0445c86b69e6"
RBAC_RETRY_ATTEMPTS="${RBAC_RETRY_ATTEMPTS:-6}"
RBAC_RETRY_DELAY_SECONDS="${RBAC_RETRY_DELAY_SECONDS:-5}"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

validate_ipv4_cidr() {
  local cidr="$1" address prefix octet
  local -a octets

  [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
  address="${cidr%/*}"
  prefix="${cidr#*/}"
  ((10#$prefix <= 32)) || return 1

  IFS=. read -r -a octets <<<"$address"
  ((${#octets[@]} == 4)) || return 1
  for octet in "${octets[@]}"; do
    ((10#$octet <= 255)) || return 1
  done
}

ipv4_cidr_bounds() {
  local cidr="$1" address prefix first second third fourth ip mask start end

  address="${cidr%/*}"
  prefix="${cidr#*/}"
  IFS=. read -r first second third fourth <<<"$address"
  ip=$(((10#$first << 24) | (10#$second << 16) | (10#$third << 8) | 10#$fourth))
  if ((10#$prefix == 0)); then
    mask=0
  else
    mask=$(((0xffffffff << (32 - 10#$prefix)) & 0xffffffff))
  fi
  start=$((ip & mask))
  end=$((start | (0xffffffff ^ mask)))
  printf '%s %s\n' "$start" "$end"
}

cidr_contains() {
  local outer="$1" inner="$2" outer_start outer_end inner_start inner_end
  read -r outer_start outer_end <<<"$(ipv4_cidr_bounds "$outer")"
  read -r inner_start inner_end <<<"$(ipv4_cidr_bounds "$inner")"
  ((inner_start >= outer_start && inner_end <= outer_end))
}

validate_key_vault_name() {
  local name="$1"
  ((${#name} >= 3 && ${#name} <= 24)) || return 1
  [[ "$name" =~ ^[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9]$ ]] || return 1
  [[ "$name" != *--* ]]
}

validate_ssh_public_key_file() {
  local file="$1" key_line="" line key_type key_blob
  local line_count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_count += 1))
    ((line_count == 1)) || return 1
    key_line="$line"
  done <"$file"
  ((line_count == 1)) || return 1

  [[ "$key_line" =~ ^([^[:space:]]+)[[:space:]]+([A-Za-z0-9+/]+={0,2})([[:space:]]+.*)?$ ]] || return 1
  key_type="${BASH_REMATCH[1]}"
  key_blob="${BASH_REMATCH[2]}"
  [[ -n "$key_blob" ]] || return 1

  case "$key_type" in
    ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|\
      sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

require_equal() {
  local resource="$1" property="$2" expected="$3" actual="$4"
  local expected_normalized actual_normalized
  expected_normalized="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  actual_normalized="$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')"
  [[ "$actual_normalized" == "$expected_normalized" ]] ||
    fail "$resource has incompatible $property: expected '$expected', found '${actual:-<empty>}'"
}

az_value() {
  local query="$1"
  shift
  az "$@" --subscription "$SUBSCRIPTION_ID" --query "$query" --output tsv
}

resource_exists() {
  local lookup_error resource_id

  if resource_id="$(az "$@" --subscription "$SUBSCRIPTION_ID" --query id --output tsv 2>&1)"; then
    [[ -n "$resource_id" && "$resource_id" != "null" ]] ||
      fail "Azure resource lookup returned no resource ID for: az $*"
    return 0
  fi

  lookup_error="$resource_id"
  case "$lookup_error" in
    *"(ResourceNotFound)"*|*"(ResourceGroupNotFound)"*|*"(ParentResourceNotFound)"*|*"(VaultNotFound)"*)
      return 1
      ;;
    *)
      fail "Azure resource lookup failed for 'az $*': ${lookup_error:-unknown Azure CLI error}"
      ;;
  esac
}

# Complete all local and authentication checks before the first resource mutation.
command -v az >/dev/null 2>&1 || fail "Azure CLI is required"
[[ -n "$SSH_CIDR" ]] || fail "Set SSH_CIDR, for example 203.0.113.4/32"
validate_ipv4_cidr "$SSH_CIDR" || fail "SSH_CIDR must be a single valid IPv4 CIDR"
validate_ipv4_cidr "$VNET_CIDR" || fail "VNET_CIDR must be a single valid IPv4 CIDR"
validate_ipv4_cidr "$SUBNET_CIDR" || fail "SUBNET_CIDR must be a single valid IPv4 CIDR"
cidr_contains "$VNET_CIDR" "$SUBNET_CIDR" ||
  fail "SUBNET_CIDR $SUBNET_CIDR must be fully contained within VNET_CIDR $VNET_CIDR"
[[ -r "$SSH_PUBLIC_KEY_FILE" && -s "$SSH_PUBLIC_KEY_FILE" ]] ||
  fail "Missing or empty public key: $SSH_PUBLIC_KEY_FILE"
validate_ssh_public_key_file "$SSH_PUBLIC_KEY_FILE" ||
  fail "SSH_PUBLIC_KEY_FILE must contain exactly one supported OpenSSH public key, not a private key"
[[ -n "$KEY_VAULT" ]] || fail "Set KEY_VAULT to a globally unique Azure Key Vault name"
validate_key_vault_name "$KEY_VAULT" ||
  fail "KEY_VAULT must be 3-24 characters, start with a letter, and contain only letters, numbers, or single hyphens"
[[ "$BOOT_DISK_GB" =~ ^[0-9]+$ ]] || fail "BOOT_DISK_GB must be a whole number"
((10#$BOOT_DISK_GB >= 30)) || fail "BOOT_DISK_GB must be at least 30 GiB"
[[ "$RBAC_RETRY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || fail "RBAC_RETRY_ATTEMPTS must be positive"
[[ "$RBAC_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || fail "RBAC_RETRY_DELAY_SECONDS must be nonnegative"
[[ "$RBAC_RETRY_ATTEMPTS" =~ ^([1-9]|1[0-9]|20)$ ]] ||
  fail "RBAC_RETRY_ATTEMPTS must be between 1 and 20"
[[ "$RBAC_RETRY_DELAY_SECONDS" =~ ^([0-9]|[1-5][0-9]|60)$ ]] ||
  fail "RBAC_RETRY_DELAY_SECONDS must be between 0 and 60"

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  SUBSCRIPTION_ID="$(az account show --query id --output tsv 2>/dev/null)" ||
    fail "Azure CLI is not authenticated; run az login"
else
  az account show --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1 ||
    fail "Cannot access Azure subscription $SUBSCRIPTION_ID; run az login and verify access"
fi
[[ -n "$SUBSCRIPTION_ID" ]] || fail "Azure CLI did not return a subscription ID"

printf 'Provisioning %s in subscription %s (%s)\n' "$VM_NAME" "$SUBSCRIPTION_ID" "$LOCATION"

group_exists="$(az group exists --name "$RESOURCE_GROUP" --subscription "$SUBSCRIPTION_ID" --output tsv)" ||
  fail "Could not check whether resource group $RESOURCE_GROUP exists"
case "$group_exists" in
  true|false) ;;
  *) fail "Azure CLI returned an unexpected resource-group existence result: ${group_exists:-<empty>}" ;;
esac

if [[ "$group_exists" == "true" ]]; then
  group_location="$(az_value location group show --name "$RESOURCE_GROUP")"
  require_equal "$RESOURCE_GROUP" location "$LOCATION" "$group_location"
else
  az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

if resource_exists network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME"; then
  vnet_location="$(az_value location network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME")"
  vnet_cidr="$(az_value 'addressSpace.addressPrefixes[0]' network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME")"
  require_equal "$VNET_NAME" location "$LOCATION" "$vnet_location"
  require_equal "$VNET_NAME" address-prefix "$VNET_CIDR" "$vnet_cidr"

  if resource_exists network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME"; then
    subnet_cidr="$(az_value addressPrefix network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$SUBNET_NAME")"
    require_equal "$SUBNET_NAME" address-prefix "$SUBNET_CIDR" "$subnet_cidr"
  else
    az network vnet subnet create \
      --resource-group "$RESOURCE_GROUP" \
      --vnet-name "$VNET_NAME" \
      --name "$SUBNET_NAME" \
      --address-prefixes "$SUBNET_CIDR" \
      --subscription "$SUBSCRIPTION_ID" \
      --output none
  fi
else
  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    --location "$LOCATION" \
    --address-prefixes "$VNET_CIDR" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefixes "$SUBNET_CIDR" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

if resource_exists network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME"; then
  nsg_location="$(az_value location network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME")"
  require_equal "$NSG_NAME" location "$LOCATION" "$nsg_location"
else
  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NSG_NAME" \
    --location "$LOCATION" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

nsg_rule_args=(
  --resource-group "$RESOURCE_GROUP"
  --nsg-name "$NSG_NAME"
  --name "$NSG_RULE_NAME"
  --priority 1000
  --direction Inbound
  --access Allow
  --protocol Tcp
  --source-address-prefixes "$SSH_CIDR"
  --source-port-ranges '*'
  --destination-address-prefixes '*'
  --destination-port-ranges 22
  --subscription "$SUBSCRIPTION_ID"
  --output none
)
if resource_exists network nsg rule show --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" --name "$NSG_RULE_NAME"; then
  az network nsg rule update "${nsg_rule_args[@]}"
else
  az network nsg rule create "${nsg_rule_args[@]}"
fi

if resource_exists network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME"; then
  public_ip_location="$(az_value location network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME")"
  public_ip_allocation="$(az_value publicIPAllocationMethod network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME")"
  public_ip_sku="$(az_value sku.name network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME")"
  public_ip_version="$(az_value publicIPAddressVersion network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME")"
  require_equal "$PUBLIC_IP_NAME" location "$LOCATION" "$public_ip_location"
  require_equal "$PUBLIC_IP_NAME" allocation-method Static "$public_ip_allocation"
  require_equal "$PUBLIC_IP_NAME" SKU Standard "$public_ip_sku"
  require_equal "$PUBLIC_IP_NAME" IP-version IPv4 "$public_ip_version"
else
  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --location "$LOCATION" \
    --allocation-method Static \
    --sku Standard \
    --version IPv4 \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

expected_subnet_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$VNET_NAME/subnets/$SUBNET_NAME"
expected_nsg_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups/$NSG_NAME"
expected_public_ip_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/publicIPAddresses/$PUBLIC_IP_NAME"
expected_nic_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkInterfaces/$NIC_NAME"

if resource_exists network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME"; then
  nic_location="$(az_value location network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME")"
  nic_subnet_id="$(az_value 'ipConfigurations[0].subnet.id' network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME")"
  nic_nsg_id="$(az_value networkSecurityGroup.id network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME")"
  nic_public_ip_id="$(az_value 'ipConfigurations[0].publicIPAddress.id' network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME")"
  require_equal "$NIC_NAME" location "$LOCATION" "$nic_location"
  require_equal "$NIC_NAME" subnet "$expected_subnet_id" "$nic_subnet_id"
  require_equal "$NIC_NAME" network-security-group "$expected_nsg_id" "$nic_nsg_id"
  require_equal "$NIC_NAME" public-IP "$expected_public_ip_id" "$nic_public_ip_id"
else
  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --location "$LOCATION" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --network-security-group "$NSG_NAME" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

if resource_exists vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME"; then
  vm_location="$(az_value location vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_size="$(az_value hardwareProfile.vmSize vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_security="$(az_value securityProfile.securityType vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_secure_boot="$(az_value securityProfile.uefiSettings.secureBootEnabled vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_vtpm="$(az_value securityProfile.uefiSettings.vTpmEnabled vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_disk_size="$(az_value storageProfile.osDisk.diskSizeGb vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_disk_sku="$(az_value storageProfile.osDisk.managedDisk.storageAccountType vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_nic_id="$(az_value 'networkProfile.networkInterfaces[0].id' vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_image_publisher="$(az_value storageProfile.imageReference.publisher vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_image_offer="$(az_value storageProfile.imageReference.offer vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  vm_image_sku="$(az_value storageProfile.imageReference.sku vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME")"
  require_equal "$VM_NAME" location "$LOCATION" "$vm_location"
  require_equal "$VM_NAME" size "$VM_SIZE" "$vm_size"
  require_equal "$VM_NAME" security-type TrustedLaunch "$vm_security"
  require_equal "$VM_NAME" secure-boot true "$vm_secure_boot"
  require_equal "$VM_NAME" vTPM true "$vm_vtpm"
  require_equal "$VM_NAME" OS-disk-size "$BOOT_DISK_GB" "$vm_disk_size"
  require_equal "$VM_NAME" OS-disk-SKU "$BOOT_DISK_SKU" "$vm_disk_sku"
  require_equal "$VM_NAME" NIC "$expected_nic_id" "$vm_nic_id"
  require_equal "$VM_NAME" image-publisher Canonical "$vm_image_publisher"
  require_equal "$VM_NAME" image-offer ubuntu-24_04-lts "$vm_image_offer"
  require_equal "$VM_NAME" image-SKU server "$vm_image_sku"
else
  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --location "$LOCATION" \
    --nics "$NIC_NAME" \
    --image "$IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USER" \
    --authentication-type ssh \
    --ssh-key-values "$SSH_PUBLIC_KEY_FILE" \
    --assign-identity \
    --security-type TrustedLaunch \
    --enable-secure-boot true \
    --enable-vtpm true \
    --os-disk-size-gb "$BOOT_DISK_GB" \
    --storage-sku "$BOOT_DISK_SKU" \
    --os-disk-delete-option Detach \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
fi

# Reconcile the safe mutable VM properties without resizing or replacing it.
principal_id="$(az_value principalId vm identity show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" 2>/dev/null || true)"
if [[ -z "$principal_id" || "$principal_id" == "null" ]]; then
  az vm identity assign \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --subscription "$SUBSCRIPTION_ID" \
    --output none

  principal_id=""
  for ((attempt = 1; attempt <= RBAC_RETRY_ATTEMPTS; attempt++)); do
    principal_id="$(az_value principalId vm identity show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" 2>/dev/null || true)"
    if [[ -n "$principal_id" && "$principal_id" != "null" ]]; then
      break
    fi
    if ((attempt < RBAC_RETRY_ATTEMPTS)); then
      printf 'Managed identity principal ID is still propagating; retrying (%d/%d).\n' \
        "$attempt" "$RBAC_RETRY_ATTEMPTS" >&2
      sleep "$RBAC_RETRY_DELAY_SECONDS"
    fi
  done
fi
[[ -n "$principal_id" && "$principal_id" != "null" ]] || fail "Azure did not return the VM managed-identity principal ID"

az vm update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --set storageProfile.osDisk.deleteOption=Detach \
  --subscription "$SUBSCRIPTION_ID" \
  --output none

if resource_exists keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEY_VAULT"; then
  vault_location="$(az_value location keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEY_VAULT")"
  vault_rbac="$(az_value properties.enableRbacAuthorization keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEY_VAULT")"
  require_equal "$KEY_VAULT" location "$LOCATION" "$vault_location"
  require_equal "$KEY_VAULT" RBAC-mode true "$vault_rbac"
  vault_id="$(az_value id keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEY_VAULT")"
else
  az keyvault create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$KEY_VAULT" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    --subscription "$SUBSCRIPTION_ID" \
    --output none
  vault_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT"
fi
[[ -n "$vault_id" ]] || fail "Azure did not return the Key Vault resource ID"

role_count="$(
  az role assignment list \
    --assignee-object-id "$principal_id" \
    --role "$SECRETS_USER_ROLE_ID" \
    --scope "$vault_id" \
    --subscription "$SUBSCRIPTION_ID" \
    --fill-principal-name false \
    --query 'length(@)' \
    --output tsv
)"
[[ "$role_count" =~ ^[0-9]+$ ]] ||
  fail "Azure CLI returned an invalid Key Vault role-assignment count: ${role_count:-<empty>}"
if ((10#$role_count == 0)); then
  role_created=false
  for ((attempt = 1; attempt <= RBAC_RETRY_ATTEMPTS; attempt++)); do
    if az role assignment create \
      --assignee-object-id "$principal_id" \
      --assignee-principal-type ServicePrincipal \
      --role "$SECRETS_USER_ROLE_ID" \
      --scope "$vault_id" \
      --subscription "$SUBSCRIPTION_ID" \
      --output none; then
      role_created=true
      break
    fi
    if ((attempt < RBAC_RETRY_ATTEMPTS)); then
      printf 'Managed identity is still propagating; retrying role assignment (%d/%d).\n' \
        "$attempt" "$RBAC_RETRY_ATTEMPTS" >&2
      sleep "$RBAC_RETRY_DELAY_SECONDS"
    fi
  done
  [[ "$role_created" == true ]] ||
    fail "Could not grant Key Vault access after $RBAC_RETRY_ATTEMPTS attempts; retry provisioning after identity propagation"
fi

public_ip="$(az_value ipAddress network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME" 2>/dev/null || printf 'unavailable')"
private_ip="$(az_value 'ipConfigurations[0].privateIPAddress' network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME" 2>/dev/null || printf 'unavailable')"
power_state="$(az_value 'instanceView.statuses[?starts_with(code, `PowerState/`)].displayStatus | [0]' vm get-instance-view --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" 2>/dev/null || printf 'unavailable')"
resolved_image="$(az_value storageProfile.imageReference.exactVersion vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" 2>/dev/null || printf 'unavailable')"

printf '\nAzure devenv host ready:\n'
printf '  Subscription: %s\n' "$SUBSCRIPTION_ID"
printf '  Resource group: %s\n' "$RESOURCE_GROUP"
printf '  VM: %s (%s, %s)\n' "$VM_NAME" "$VM_SIZE" "${power_state:-unavailable}"
printf '  Public/private IP: %s / %s\n' "${public_ip:-unavailable}" "${private_ip:-unavailable}"
printf '  Managed identity: %s\n' "$principal_id"
printf '  OS disk: %s GiB %s (delete option: Detach)\n' "$BOOT_DISK_GB" "$BOOT_DISK_SKU"
printf '  Image: %s (resolved version: %s)\n' "$IMAGE" "${resolved_image:-unavailable}"
printf '  Key Vault: %s\n' "$KEY_VAULT"
