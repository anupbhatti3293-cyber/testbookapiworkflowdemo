#!/bin/bash

# ============================================================
# Testbook API - EKS Cluster Creation
#
# Creates an AWS EKS cluster for the Testbook API demo.
#
# Cluster : testbook-cluster
# Region  : eu-north-1
# Nodes   : 2
# Type    : t3.small
# ============================================================

set -e

CLUSTER_NAME="testbook-cluster"
REGION="eu-north-1"
NODEGROUP_NAME="demo-workers"
NODE_TYPE="t3.small"
NODES=2

# ------------------------------------------------------------
# Start timer
# ------------------------------------------------------------
# Store the current time in seconds.
# At the end of the script, we compare this with the finish
# time to calculate how long the complete process took.
# ------------------------------------------------------------

START_TIME=$(date +%s)

echo "============================================================"
echo " Creating EKS cluster: $CLUSTER_NAME"
echo " Region: $REGION"
echo " Worker nodes: $NODES x $NODE_TYPE"
echo "============================================================"


# ------------------------------------------------------------
# Step 1: Check that the required command-line tools exist
# ------------------------------------------------------------

echo ""
echo "Checking required tools..."

command -v aws >/dev/null 2>&1 || {
    echo "ERROR: AWS CLI is not installed."
    exit 1
}

command -v eksctl >/dev/null 2>&1 || {
    echo "ERROR: eksctl is not installed."
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo "ERROR: kubectl is not installed."
    exit 1
}

echo "Required tools are available."


# ------------------------------------------------------------
# Step 2: Check AWS login
# ------------------------------------------------------------

echo ""
echo "Checking AWS credentials..."

aws sts get-caller-identity

echo ""
echo "AWS credentials are working."


# ------------------------------------------------------------
# Step 3: Create the EKS cluster
# ------------------------------------------------------------
#
# eksctl creates:
#
#   EKS Control Plane
#          |
#          |
#      Node Group
#          |
#      +---+---+
#      |       |
#    EC2       EC2
#    Node 1    Node 2
#
# --managed tells AWS to create an EKS managed node group.
# ------------------------------------------------------------

echo ""
echo "Creating EKS cluster..."
echo "This can take around 15-25 minutes."

eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --nodegroup-name "$NODEGROUP_NAME" \
  --node-type "$NODE_TYPE" \
  --nodes "$NODES" \
  --nodes-min "$NODES" \
  --nodes-max "$NODES" \
  --managed


# ------------------------------------------------------------
# Step 4: Configure kubectl
# ------------------------------------------------------------
#
# This tells kubectl which EKS cluster it should communicate
# with.
# ------------------------------------------------------------

echo ""
echo "Updating kubeconfig..."

aws eks update-kubeconfig \
  --region "$REGION" \
  --name "$CLUSTER_NAME"


# ------------------------------------------------------------
# Step 5: Wait until the worker nodes are ready
# ------------------------------------------------------------

echo ""
echo "Waiting for Kubernetes nodes to become Ready..."

kubectl wait \
  --for=condition=Ready \
  nodes \
  --all \
  --timeout=10m


# ------------------------------------------------------------
# Step 6: Display the worker nodes
# ------------------------------------------------------------

echo ""
echo "Worker nodes:"

kubectl get nodes -o wide


# ------------------------------------------------------------
# Step 7: Check Kubernetes system pods
# ------------------------------------------------------------

echo ""
echo "Kubernetes system pods:"

kubectl get pods -n kube-system


# ------------------------------------------------------------
# Step 8: Display final cluster information
# ------------------------------------------------------------

echo ""
echo "EKS cluster:"

aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.{Name:name,Status:status,Version:version}" \
  --output table


# ------------------------------------------------------------
# Step 9: Calculate total execution time
# ------------------------------------------------------------
#
# Capture the finish time and subtract the start time.
# The result is converted into minutes and seconds.
# ------------------------------------------------------------

END_TIME=$(date +%s)

TOTAL_SECONDS=$((END_TIME - START_TIME))

MINUTES=$((TOTAL_SECONDS / 60))
SECONDS=$((TOTAL_SECONDS % 60))


# ------------------------------------------------------------
# Final result
# ------------------------------------------------------------

echo ""
echo "============================================================"
echo " EKS CLUSTER CREATED SUCCESSFULLY"
echo "============================================================"
echo ""
echo "Cluster : $CLUSTER_NAME"
echo "Region  : $REGION"
echo "Nodes   : $NODES x $NODE_TYPE"
echo ""
echo "Total time taken: ${MINUTES} minutes ${SECONDS} seconds"
echo ""
echo "You can now deploy the Testbook API."
echo "============================================================"