#!/usr/bin/env bash
set -euo pipefail

echo "================= GCP DR VM LAUNCH (Same Project) ================="

choose_from_list() {
  local prompt="$1"; shift
  local -n arr=$1
  echo "$prompt"
  for i in "${!arr[@]}"; do
    printf "%s) %s\n" "$((i+1))" "${arr[$i]}"
  done
  local choice
  while true; do
    read -rp "Enter choice [1-${#arr[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#arr[@]} )); then
      REPLY="${arr[$((choice-1))]}"
      return
    fi
    echo "Invalid choice, try again."
  done
}

read -rp "Enter GCP Project ID (where machine image & VM exist): " PROJECT
read -rp "Enter Source Machine Image Name: " SRC_MI
read -rp "Enter Host VPC Project ID (Shared VPC host): " HOST_NET_PROJECT
read -rp "Enter VPC Network Name (e.g., prod-vpc-gcp-opl): " NET_NAME

# REGION MENU
echo
REGIONS=("asia-south1" "asia-south2")
choose_from_list "🔍 Select Region (India only):" REGIONS
REGION="$REPLY"

# ZONES MENU
echo
mapfile -t ZONES < <(gcloud compute zones list \
  --project="$PROJECT" \
  --filter="region:$REGION" \
  --format="value(name)")
if (( ${#ZONES[@]} == 0 )); then echo "❌ No zones found"; exit 1; fi
choose_from_list "🔍 Select Zone for region $REGION:" ZONES
ZONE="$REPLY"

# SUBNET MENU
echo
mapfile -t SUBNETS < <(
  gcloud compute networks subnets list \
    --network="$NET_NAME" \
    --project="$HOST_NET_PROJECT" \
    --filter="region:$REGION AND privateIpGoogleAccess:true" \
    --format="value(name)"
)
if (( ${#SUBNETS[@]} == 0 )); then echo "❌ No private subnets found"; exit 1; fi
choose_from_list "🔍 Select Private Subnet in $REGION:" SUBNETS
SUBNET="$REPLY"

# CMEK MENU
echo
KMS_KEYS=()
for LOC in asia-south1 asia-south2; do
  mapfile -t KRINGS < <(gcloud kms keyrings list --project="$PROJECT" --location="$LOC" --format="value(name)" 2>/dev/null || true)
  for KR in "${KRINGS[@]}"; do
    mapfile -t KEYS < <(gcloud kms keys list --project="$PROJECT" --location="$LOC" --keyring="$KR" --format="value(name)" 2>/dev/null || true)
    for KEY in "${KEYS[@]}"; do KMS_KEYS+=("$KEY"); done
  done
done
if (( ${#KMS_KEYS[@]} == 0 )); then echo "❌ No CMEK keys found"; exit 1; fi
choose_from_list "🔍 Select CMEK encryption key:" KMS_KEYS
KMS_SELECTED="$REPLY"

# SERVICE ACCOUNT MENU
echo
mapfile -t SERVICE_ACCOUNTS < <(gcloud iam service-accounts list --project="$PROJECT" --format="value(email)")
if (( ${#SERVICE_ACCOUNTS[@]} == 0 )); then echo "❌ No service accounts"; exit 1; fi
choose_from_list "🔍 Select Service Account:" SERVICE_ACCOUNTS
SA_EMAIL="$REPLY"

echo
read -rp "Enter Destination VM Instance Name: " DEST_VM

echo
echo "=========== SUMMARY ==========="
printf "%-20s %s\n" "Project:" "$PROJECT"
printf "%-20s %s\n" "Machine Image:" "$SRC_MI"
printf "%-20s %s\n" "Region:" "$REGION"
printf "%-20s %s\n" "Zone:" "$ZONE"
printf "%-20s %s\n" "Subnet:" "$SUBNET"
printf "%-20s %s\n" "KMS Key:" "$KMS_SELECTED"
printf "%-20s %s\n" "Service Account:" "$SA_EMAIL"
printf "%-20s %s\n\n" "VM Name:" "$DEST_VM"
read -rp "Launch VM now? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && exit 0

echo
gcloud compute instances create "$DEST_VM" \
  --source-machine-image "projects/$PROJECT/global/machineImages/$SRC_MI" \
  --zone="$ZONE" \
  --network="projects/$HOST_NET_PROJECT/global/networks/$NET_NAME" \
  --subnet="projects/$HOST_NET_PROJECT/regions/$REGION/subnetworks/$SUBNET" \
  --project="$PROJECT" \
  --service-account="$SA_EMAIL" \
  --instance-kms-key="$KMS_SELECTED" \
  --no-address

echo
echo "🎉 SUCCESS — DR VM Created"
echo "VM: $DEST_VM  |  Region: $REGION  |  Zone: $ZONE"

