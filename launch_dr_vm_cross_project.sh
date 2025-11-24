#!/usr/bin/env bash
set -euo pipefail

echo "================= GCP DR VM LAUNCH (Cross Project) ================="

# Helper for menu selection
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

read -rp "Enter SOURCE Project ID (where machine image exists): " SRC_PROJECT
read -rp "Enter DESTINATION Project ID (where VM will be created): " DEST_PROJECT
read -rp "Enter Source Machine Image Name: " SRC_MI
read -rp "Enter Host VPC Project ID (Shared VPC host): " HOST_NET_PROJECT
read -rp "Enter VPC Network Name (e.g., prod-vpc-gcp-opl): " NET_NAME

# Region menu
echo
REGIONS=("asia-south1" "asia-south2")
choose_from_list "🔍 Select Region for DESTINATION VM (India only):" REGIONS
REGION="$REPLY"

# Zone menu
echo
mapfile -t ZONES < <(gcloud compute zones list \
  --project="$DEST_PROJECT" \
  --filter="region:$REGION" \
  --format="value(name)")
if (( ${#ZONES[@]} == 0 )); then echo "❌ No zones found"; exit 1; fi
choose_from_list "🔍 Select Zone in $REGION:" ZONES
ZONE="$REPLY"

# Subnet menu
echo
mapfile -t SUBNETS < <(
  gcloud compute networks subnets list \
    --network="$NET_NAME" \
    --project="$HOST_NET_PROJECT" \
    --filter="region:$REGION AND privateIpGoogleAccess:true" \
    --format="value(name)"
)
if (( ${#SUBNETS[@]} == 0 )); then echo "❌ No PRIVATE subnets found"; exit 1; fi
choose_from_list "🔍 Select Private Subnet in $REGION:" SUBNETS
SUBNET="$REPLY"

# CMEK menu (Destination project only)
echo
KMS_KEYS=()
for LOC in asia-south1 asia-south2; do
  mapfile -t KRINGS < <(
    gcloud kms keyrings list --project="$DEST_PROJECT" --location="$LOC" --format="value(name)" 2>/dev/null || true
  )
  for KR in "${KRINGS[@]}"; do
    mapfile -t KEYS < <(
      gcloud kms keys list --project="$DEST_PROJECT" --location="$LOC" --keyring="$KR" --format="value(name)" 2>/dev/null || true
    )
    for KEY in "${KEYS[@]}"; do KMS_KEYS+=("$KEY"); done
  done
done
if (( ${#KMS_KEYS[@]} == 0 )); then echo "❌ No CMEK keys found in DESTINATION project"; exit 1; fi
choose_from_list "🔍 Select DESTINATION CMEK encryption key:" KMS_KEYS
KMS_SELECTED="$REPLY"

# Service Account (Destination project)
echo
mapfile -t SERVICE_ACCOUNTS < <(
  gcloud iam service-accounts list \
    --project="$DEST_PROJECT" \
    --format="value(email)"
)
if (( ${#SERVICE_ACCOUNTS[@]} == 0 )); then echo "❌ No SAs in DESTINATION project"; exit 1; fi
choose_from_list "🔍 Select Service Account for VM:" SERVICE_ACCOUNTS
SA_EMAIL="$REPLY"

echo
read -rp "Enter Destination VM Instance Name: " DEST_VM

# IAM warning
DEST_PROJ_NUM=$(gcloud projects describe "$DEST_PROJECT" --format="value(projectNumber)")
CLOUD_SVC_SA="${DEST_PROJ_NUM}@cloudservices.gserviceaccount.com"
echo
echo "⚠ IAM Validation Reminder"
echo "The following SA must have roles/compute.imageUser on Source project:"
echo "  serviceAccount:$CLOUD_SVC_SA"
echo "Otherwise: VM launch will FAIL (403 error)"
echo

echo "=========== FINAL SUMMARY ==========="
printf "%-22s %s\n" "Source Project:" "$SRC_PROJECT"
printf "%-22s %s\n" "Destination Project:" "$DEST_PROJECT"
printf "%-22s %s\n" "Machine Image:" "$SRC_MI"
printf "%-22s %s\n" "Region:" "$REGION"
printf "%-22s %s\n" "Zone:" "$ZONE"
printf "%-22s %s\n" "Subnet:" "$SUBNET"
printf "%-22s %s\n" "CMEK Key:" "$KMS_SELECTED"
printf "%-22s %s\n" "Service Account:" "$SA_EMAIL"
printf "%-22s %s\n\n" "VM Name:" "$DEST_VM"
read -rp "Launch VM now? (y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && exit 0

echo
echo "🚀 Launching Cross-Project VM..."
gcloud compute instances create "$DEST_VM" \
  --source-machine-image "projects/$SRC_PROJECT/global/machineImages/$SRC_MI" \
  --zone="$ZONE" \
  --network="projects/$HOST_NET_PROJECT/global/networks/$NET_NAME" \
  --subnet="projects/$HOST_NET_PROJECT/regions/$REGION/subnetworks/$SUBNET" \
  --project="$DEST_PROJECT" \
  --service-account="$SA_EMAIL" \
  --instance-kms-key="$KMS_SELECTED" \
  --no-address

echo
echo "🎉 SUCCESS — Cross-Project DR VM Created"
echo "VM: $DEST_VM | Project: $DEST_PROJECT | Region: $REGION | Zone: $ZONE"
echo "==============================================================="

