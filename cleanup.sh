#!/bin/bash

# ============================================================
# Testbook API - EKS Complete Cleanup Script
# ============================================================
#
# This script:
#
# 1. Deletes the Argo CD Application
# 2. Uninstalls the Helm release (if one exists)
# 3. Deletes the DEV namespace
# 4. Deletes the complete EKS cluster
# 5. Verifies remaining EKS clusters
# 6. Verifies remaining EC2 instances
# 7. Verifies remaining Load Balancers
# 8. Calculates and displays total cleanup time
#
# ============================================================


# ============================================================
# START TIMER
# ============================================================

START_TIME=$(date +%s)

echo "=============================================="
echo " TESTBOOK API - CLEANUP STARTED"
echo "=============================================="
echo ""
echo "Start time: $(date)"
echo ""


# ============================================================
# STEP 1 - DELETE ARGO CD APPLICATION
# ============================================================

echo "Deleting Argo CD application..."

kubectl delete application testbook-api \
  -n argocd \
  --ignore-not-found=true

echo ""


# ============================================================
# STEP 2 - UNINSTALL HELM RELEASE
# ============================================================
#
# This command is harmless if the application was deployed
# entirely by Argo CD and no Helm release exists.
#
# ============================================================

echo "Checking/removing Helm release..."

helm uninstall testbook-api -n dev 2>/dev/null || true

echo ""


# ============================================================
# STEP 3 - DELETE DEV NAMESPACE
# ============================================================

echo "Deleting DEV namespace..."

kubectl delete namespace dev \
  --ignore-not-found=true

echo ""


# ============================================================
# STEP 4 - DELETE EKS CLUSTER
# ============================================================
#
# --wait means eksctl waits until the cluster deletion
# has completed before continuing.
#
# This is normally the longest-running step.
#
# ============================================================

echo "=============================================="
echo " Deleting EKS cluster..."
echo "=============================================="

eksctl delete cluster \
  --name testbook-cluster \
  --region eu-north-1 \
  --wait

echo ""


# ============================================================
# STEP 5 - VERIFY CLEANUP
# ============================================================

echo "=============================================="
echo " CLEANUP COMPLETE"
echo "=============================================="

echo ""

echo "Remaining EKS clusters:"
aws eks list-clusters \
  --region eu-north-1

echo ""


# ============================================================
# CHECK REMAINING EC2 INSTANCES
# ============================================================

echo "Remaining EC2 instances:"

aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name,Type:InstanceType}" \
  --output table

echo ""


# ============================================================
# CHECK REMAINING LOAD BALANCERS
# ============================================================

echo "Remaining Load Balancers:"

aws elbv2 describe-load-balancers \
  --region eu-north-1 \
  --query "LoadBalancers[].{Name:LoadBalancerName,DNS:DNSName}" \
  --output table

echo ""


# ============================================================
# END TIMER
# ============================================================

END_TIME=$(date +%s)

TOTAL_SECONDS=$((END_TIME - START_TIME))

MINUTES=$((TOTAL_SECONDS / 60))
SECONDS=$((TOTAL_SECONDS % 60))


# ============================================================
# DISPLAY TOTAL CLEANUP TIME
# ============================================================

echo "=============================================="
echo " CLEANUP SUMMARY"
echo "=============================================="
echo ""
echo "End time: $(date)"
echo ""
echo "Total cleanup time:"
echo "${MINUTES} minutes ${SECONDS} seconds"
echo ""
echo "Total seconds:"
echo "${TOTAL_SECONDS} seconds"
echo ""
echo "=============================================="
echo " CLEANUP FINISHED"
echo "=============================================="