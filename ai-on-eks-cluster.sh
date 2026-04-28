#!/bin/bash

# Set AWS account ID, region, and cluster name
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-164018255983}"
export AWS_REGION="${AWS_REGION:-ap-southeast-2}"
CLUSTER_NAME="ai-on-eks-image-cluster"
USE_SPOT="${USE_SPOT:-false}"
K8S_VERSION="${K8S_VERSION:-1.35}"

echo "Using AWS Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION, Spot: $USE_SPOT"

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
  echo "Creating CPU EKS cluster in $AWS_REGION (spot=$USE_SPOT)..."
  START_TIME=$(date +%s)

  local spot_args=()
  if [ "$USE_SPOT" = "true" ]; then
    spot_args=(--spot --instance-types m5.xlarge,m5a.xlarge,m4.xlarge)
  else
    spot_args=(--node-type m5.xlarge)
  fi

  if ! eksctl create cluster \
    --name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --version "$K8S_VERSION" \
    "${spot_args[@]}" \
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

check_gpu_quota() {
  local quota_code
  local quota_label
  if [ "$USE_SPOT" = "true" ]; then
    quota_code="L-3819A6DF"
    quota_label="All G and VT Spot Instance Requests"
  else
    quota_code="L-DB2E81BA"
    quota_label="Running On-Demand G and VT instances"
  fi

  echo "Checking GPU vCPU quota ($quota_label) in $AWS_REGION..."
  local quota
  quota=$(aws service-quotas get-service-quota \
    --region "$AWS_REGION" \
    --service-code ec2 \
    --quota-code "$quota_code" \
    --query "Quota.Value" \
    --output text 2>/dev/null)

  if [ -z "$quota" ] || [ "$quota" = "None" ]; then
    echo "⚠️  Could not retrieve GPU quota. Proceeding anyway..."
    return 0
  fi

  local required=4  # g4dn.xlarge has 4 vCPUs
  echo "Current $quota_label vCPU limit: $quota (need at least $required)"

  if [ "$(echo "$quota < $required" | bc)" -eq 1 ]; then
    echo "❌ Insufficient GPU vCPU quota ($quota < $required)."
    echo ""
    echo "Request an increase with:"
    echo "  aws service-quotas request-service-quota-increase \\"
    echo "    --region $AWS_REGION \\"
    echo "    --service-code ec2 \\"
    echo "    --quota-code $quota_code \\"
    echo "    --desired-value 4"
    echo ""
    echo "Or visit: https://$AWS_REGION.console.aws.amazon.com/servicequotas/home/services/ec2/quotas"
    echo "Search for '$quota_label'"
    exit 1
  fi

  echo "✅ GPU vCPU quota is sufficient."
}

start_gpu() {
  # Verify GPU quota before creating the cluster
  check_gpu_quota

  echo "Creating EKS cluster with GPU node group in $AWS_REGION (spot=$USE_SPOT)..."
  START_TIME=$(date +%s)

  # Create the base cluster first
  if ! eksctl create cluster \
    --name "${CLUSTER_NAME}-gpu" \
    --region "$AWS_REGION" \
    --version "$K8S_VERSION" \
    --without-nodegroup; then
    echo "Failed to create EKS cluster"
    exit 1
  fi

  # Add a GPU node group with g4dn.xlarge (NVIDIA T4)
  local spot_args=()
  if [ "$USE_SPOT" = "true" ]; then
    spot_args=(--spot --instance-types g4dn.xlarge,g4dn.2xlarge)
  else
    spot_args=(--node-type g4dn.xlarge)
  fi

  if ! eksctl create nodegroup \
    --cluster "${CLUSTER_NAME}-gpu" \
    --region "$AWS_REGION" \
    --name gpu-nodes \
    "${spot_args[@]}" \
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

build() {
  local ECR_REPO="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
  local IMAGE_TAG="${2:-latest}"
  local IMAGE="$ECR_REPO/ai-image-generator:$IMAGE_TAG"

  echo "Creating ECR repository (if it doesn't exist)..."
  aws ecr create-repository \
    --repository-name ai-image-generator \
    --region "$AWS_REGION" 2>/dev/null || true

  echo "Logging in to ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REPO"

  echo "Building image: $IMAGE (platform: linux/amd64)"
  docker build --platform linux/amd64 -t "$IMAGE" .

  echo "Pushing image: $IMAGE"
  docker push "$IMAGE"

  echo "✅ Image pushed successfully: $IMAGE"
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
  build)
    build "$@"
    ;;
  check)
    check_gpu_availability
    ;;
  quota)
    check_gpu_quota
    ;;
  list)
    list
    ;;
  stop)
    stop
    ;;
  *)
    echo "Usage: $0 {cpu|gpu|build|deploy|check|quota|list|stop}"
    echo "  cpu    - Create CPU cluster (slow inference)"
    echo "  gpu    - Create GPU cluster with NVIDIA T4 (fast inference)"
    echo "  build  - Build and push Docker image to ECR (default tag: latest)"
    echo "           Example: $0 build v1.0"
    echo "  deploy - Deploy manifest with variable substitution (default: k8s/gpu-deployment.yaml)"
    echo "           Example: $0 deploy k8s/deployment.yaml"
    echo "  check  - Check GPU instance availability"
    echo "  quota  - Check GPU vCPU quota"
    echo "  list   - List all EKS clusters"
    echo "  stop   - Delete all clusters"
    echo ""
    echo "Environment variables:"
    echo '  K8S_VERSION=1.35     - Kubernetes version (default: 1.35)'
    echo '  USE_SPOT=true|false  - Use spot instances (default: false)'
    echo "           Example: USE_SPOT=true $0 gpu"
    exit 1
    ;;
esac
