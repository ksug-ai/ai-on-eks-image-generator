#!/bin/bash

# Set AWS account ID, region, and cluster name
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-164018255983}"
export AWS_REGION="${AWS_REGION:-ap-southeast-4}"
CLUSTER_NAME="ai-on-eks-image-cluster"

echo "Using AWS Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"

check_gpu_availability() {
  echo "Checking GPU instance availability in $AWS_REGION..."
  aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters "Name=instance-type,Values=g4dn.*" \
    --region "$AWS_REGION" \
    --query "InstanceTypeOfferings[].{Type:InstanceType,Zone:Location}" \
    --output table
}

start_cpu() {
  echo "Creating CPU EKS cluster in $AWS_REGION..."
  START_TIME=$(date +%s)

  if ! eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --node-type m5.xlarge \
    --nodes 1 \
    --nodes-min 1 \
    --nodes-max 3 \
    --managed; then
    echo "Failed to create CPU cluster"
    exit 1
  fi

  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))
  echo "CPU cluster created successfully in ${MINUTES}m ${SECONDS}s!"
}

start_gpu() {
  echo "Creating EKS cluster with GPU node group in $AWS_REGION..."
  START_TIME=$(date +%s)

  # Create the base cluster first
  if ! eksctl create cluster \
    --name "${CLUSTER_NAME}-gpu" \
    --region "$AWS_REGION" \
    --without-nodegroup; then
    echo "Failed to create EKS cluster"
    exit 1
  fi

  # Add a GPU node group with g4dn.xlarge (NVIDIA T4)
  if ! eksctl create nodegroup \
    --cluster "${CLUSTER_NAME}-gpu" \
    --region "$AWS_REGION" \
    --name gpu-nodes \
    --node-type g4dn.xlarge \
    --nodes 1 \
    --nodes-min 0 \
    --nodes-max 2 \
    --managed; then
    echo "Failed to create GPU node group"
    exit 1
  fi

  aws eks update-kubeconfig --name "${CLUSTER_NAME}-gpu" --region "$AWS_REGION"

  # Install the NVIDIA device plugin for GPU support
  echo "Installing NVIDIA device plugin..."
  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINUTES=$((DURATION / 60))
  SECONDS=$((DURATION % 60))
  echo "GPU cluster created successfully in ${MINUTES}m ${SECONDS}s!"
}

list() {
  echo "Listing EKS clusters in $AWS_REGION..."
  eksctl get cluster --region "$AWS_REGION"
}

stop() {
  echo "Deleting EKS clusters..."
  for cluster in "$CLUSTER_NAME" "${CLUSTER_NAME}-gpu"; do
    if aws eks describe-cluster --name "$cluster" --region "$AWS_REGION" >/dev/null 2>&1; then
      echo "Deleting cluster: $cluster"
      eksctl delete cluster --name "$cluster" --region "$AWS_REGION" --wait || true
    fi
  done
  echo "Clusters deleted successfully!"
}

deploy() {
  local manifest="${2:-k8s/gpu-deployment.yaml}"
  echo "Deploying $manifest with AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID, AWS_REGION=$AWS_REGION..."
  envsubst < "$manifest" | kubectl apply -f -
  echo "Deployed successfully!"
}

case "$1" in
  cpu)
    start_cpu
    ;;
  gpu)
    start_gpu
    ;;
  deploy)
    deploy "$@"
    ;;
  check)
    check_gpu_availability
    ;;
  list)
    list
    ;;
  stop)
    stop
    ;;
  *)
    echo "Usage: $0 {cpu|gpu|deploy|check|list|stop}"
    echo "  cpu    - Create CPU cluster (slow inference)"
    echo "  gpu    - Create GPU cluster with NVIDIA T4 (fast inference)"
    echo "  deploy - Deploy manifest with variable substitution (default: k8s/gpu-deployment.yaml)"
    echo "           Example: $0 deploy k8s/deployment.yaml"
    echo "  check  - Check GPU instance availability"
    echo "  list   - List all EKS clusters"
    echo "  stop   - Delete all clusters"
    exit 1
    ;;
esac
