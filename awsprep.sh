#!/bin/bash
# awsprep.sh — Install and verify CLI prerequisites for the AI-on-EKS workshop.
# Designed for AWS CloudShell (Amazon Linux) but also works on macOS/Linux.

set -euo pipefail

OK="✅"
WARN="⚠️ "
FAIL="❌"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
ok()    { echo "$OK  $*"; }
warn()  { echo "$WARN $*"; }
fail()  { echo "$FAIL $*"; exit 1; }

# ──────────────────────────────────────────────
# 1. AWS CLI — must already be present
# ──────────────────────────────────────────────
check_aws_cli() {
  info "Checking AWS CLI..."
  if ! command -v aws &>/dev/null; then
    fail "AWS CLI not found. Install it from https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
  fi
  AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
  ok "AWS CLI found: $AWS_VERSION"

  info "Checking AWS credentials..."
  if ! aws sts get-caller-identity &>/dev/null; then
    fail "AWS credentials not configured. Run 'aws configure' or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
  fi
  IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
  ok "Authenticated as: $IDENTITY"
}

# ──────────────────────────────────────────────
# 2. kubectl — verify or install
# ──────────────────────────────────────────────
install_kubectl() {
  info "kubectl not found — installing latest stable release..."

  local OS ARCH
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')   # linux | darwin
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  local VERSION
  VERSION=$(curl -fsSL "https://dl.k8s.io/release/stable.txt")
  local URL="https://dl.k8s.io/release/${VERSION}/bin/${OS}/${ARCH}/kubectl"

  info "Downloading kubectl ${VERSION} for ${OS}/${ARCH}..."
  curl -fsSLO "$URL"
  chmod +x kubectl

  if [ -w /usr/local/bin ]; then
    mv kubectl /usr/local/bin/kubectl
  else
    sudo mv kubectl /usr/local/bin/kubectl
  fi
}

check_kubectl() {
  info "Checking kubectl..."
  if ! command -v kubectl &>/dev/null; then
    install_kubectl
  fi
  KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>&1 | head -1)
  ok "kubectl found: $KUBECTL_VERSION"
}

# ──────────────────────────────────────────────
# 3. eksctl — verify or install
# ──────────────────────────────────────────────
install_eksctl() {
  info "eksctl not found — installing latest release..."

  local OS ARCH
  OS=$(uname -s)    # Linux | Darwin
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: $ARCH" ;;
  esac

  local PLATFORM="${OS}_${ARCH}"
  local DOWNLOAD_URL="https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${PLATFORM}.tar.gz"

  info "Downloading eksctl for ${PLATFORM}..."
  curl -fsSL "$DOWNLOAD_URL" | tar -xz -C /tmp eksctl

  if [ -w /usr/local/bin ]; then
    mv /tmp/eksctl /usr/local/bin/eksctl
  else
    sudo mv /tmp/eksctl /usr/local/bin/eksctl
  fi
}

check_eksctl() {
  info "Checking eksctl..."
  if ! command -v eksctl &>/dev/null; then
    install_eksctl
  fi
  EKSCTL_VERSION=$(eksctl version)
  ok "eksctl found: $EKSCTL_VERSION"
}

# ──────────────────────────────────────────────
# 4. GPU vCPU quotas
# ──────────────────────────────────────────────
check_vcpu_quota() {
  local REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null)}"
  if [ -z "$REGION" ]; then
    warn "AWS region not set — skipping quota check. Set AWS_REGION or run 'aws configure'."
    return
  fi

  info "Checking GPU vCPU quotas in region: $REGION"

  local REQUIRED=4   # g4dn.xlarge = 4 vCPUs
  local QUOTA_FAILED=false

  # Helper: fetch a single quota value
  get_quota() {
    aws service-quotas get-service-quota \
      --region "$REGION" \
      --service-code ec2 \
      --quota-code "$1" \
      --query "Quota.Value" \
      --output text 2>/dev/null || echo ""
  }

  # Spot G & VT quota (default)
  local SPOT_CODE="L-3819A6DF"
  local SPOT_LABEL="Spot G and VT instance requests"
  local SPOT_QUOTA
  SPOT_QUOTA=$(get_quota "$SPOT_CODE")

  if [ -z "$SPOT_QUOTA" ] || [ "$SPOT_QUOTA" = "None" ]; then
    warn "Could not retrieve $SPOT_LABEL quota."
  else
    local SPOT_INT=${SPOT_QUOTA%.*}
    if [ "$SPOT_INT" -ge "$REQUIRED" ]; then
      ok "$SPOT_LABEL vCPU quota: $SPOT_INT (need ≥ $REQUIRED) [default]"
    else
      warn "$SPOT_LABEL vCPU quota: $SPOT_INT — BELOW the required $REQUIRED vCPUs."
      echo "       Request an increase:"
      echo "         aws service-quotas request-service-quota-increase \\"
      echo "           --region $REGION --service-code ec2 \\"
      echo "           --quota-code $SPOT_CODE --desired-value 4"
      QUOTA_FAILED=true
    fi
  fi

  # On-Demand G & VT quota (opt-in via USE_SPOT=false)
  local OD_CODE="L-DB2E81BA"
  local OD_LABEL="On-Demand G and VT instances"
  local OD_QUOTA
  OD_QUOTA=$(get_quota "$OD_CODE")

  if [ -z "$OD_QUOTA" ] || [ "$OD_QUOTA" = "None" ]; then
    warn "Could not retrieve $OD_LABEL quota."
  else
    local OD_INT=${OD_QUOTA%.*}
    if [ "$OD_INT" -ge "$REQUIRED" ]; then
      ok "$OD_LABEL vCPU quota: $OD_INT (need ≥ $REQUIRED)"
    else
      warn "$OD_LABEL vCPU quota: $OD_INT — BELOW the required $REQUIRED vCPUs."
      echo "       Request an increase:"
      echo "         aws service-quotas request-service-quota-increase \\"
      echo "           --region $REGION --service-code ec2 \\"
      echo "           --quota-code $OD_CODE --desired-value 4"
      QUOTA_FAILED=true
    fi
  fi

  if [ "$QUOTA_FAILED" = true ]; then
    echo ""
    warn "One or more GPU quotas are insufficient."
    echo "       Approval can take minutes to a couple of days."
    echo "       Console: https://${REGION}.console.aws.amazon.com/servicequotas/home/services/ec2/quotas"
    echo "       You can still proceed — the cluster script will re-verify before launching GPU nodes."
  fi
}


# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
echo "======================================"
echo "  AI-on-EKS Workshop — Prerequisites"
echo "======================================"
echo ""

check_aws_cli
echo ""
check_kubectl
echo ""
check_eksctl
echo ""
check_vcpu_quota
echo ""

echo "======================================"
ok  "All required tools are ready!"
echo "======================================"
echo ""
echo "Next steps:"
echo "  ./ai-on-eks-cluster.sh gpu    # Create GPU cluster"
echo "  ./ai-on-eks-cluster.sh build  # Build & push Docker image"
echo ""
