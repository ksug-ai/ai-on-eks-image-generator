# 🎨 AI Image Generator on EKS by [KSUG.AI](https://ksug.ai)

This is a hands-on workshop python app that runs **Stable Diffusion** on **Amazon Elastic Kubernetes Service (EKS)**.

📊 **Workshop Slides:** [View on Canva](https://canva.link/xvzkt8z2gr93fzi)

## 🚀 Features
- Generate AI images from text prompts
- Runs on EKS (CPU or GPU nodes)
- Scales with Kubernetes deployments

**Performance:** GPU is recommended, typically an image can be generated in ~30 seconds with NVIDIA T4 (g4dn.xlarge). For CPU, it does take 15 mins or much longer.

## 🏁 Getting Started

### Open AWS CloudShell

The easiest way to run this workshop is directly in your browser — no local installs needed. The Docker image is built and pushed automatically via GitHub Actions CI/CD.

1. Sign in to the [AWS Management Console](https://console.aws.amazon.com)
2. Click the **CloudShell** icon in the top navigation bar (terminal prompt icon, next to the search bar), or go directly to [CloudShell](https://console.aws.amazon.com/cloudshell)
3. Wait a few seconds for the shell to initialise

> CloudShell comes with AWS CLI and credentials pre-configured for your account. `eksctl` is **not** pre-installed — the prep script below handles that.

### Clone the repo

```bash
git clone https://github.com/ksug-ai/ai-on-eks-image-generator.git
cd ai-on-eks-image-generator
```

---

## Prerequisites

- AWS account with CLI configured (`aws configure`)
- `eksctl` and `kubectl` installed
- For GPU clusters: a vCPU quota of at least 4 for G and VT spot instances in your region

### 1. Run the prep script

Run this first — it installs `eksctl` and `kubectl` if missing, verifies your AWS credentials, and checks your GPU vCPU quotas:

```bash
./awsprep.sh
```

> **AWS CloudShell users:** `eksctl` is not pre-installed in CloudShell. The script handles it automatically.

If the quota check reports a value below 4, request an increase before continuing:

```bash
# Spot instances (default)
aws service-quotas request-service-quota-increase \
  --region $(aws configure get region) \
  --service-code ec2 --quota-code L-3819A6DF \
  --desired-value 4
```

```bash
# On-demand instances (USE_SPOT=false)
aws service-quotas request-service-quota-increase \
  --region $(aws configure get region) \
  --service-code ec2 --quota-code L-DB2E81BA \
  --desired-value 4
```

Approval can take minutes to a couple of days. The cluster script also re-checks the quota right before creating GPU nodes.

### 2. Create an EKS cluster

Create a GPU cluster (uses **spot instances by default**):

```bash
./ai-on-eks-cluster.sh gpu
```

To use on-demand instances instead:

```bash
USE_SPOT=false ./ai-on-eks-cluster.sh gpu
```

**Optional: Create a CPU-based EKS cluster:**
```bash
./ai-on-eks-cluster.sh cpu
```
Once the cluster is created, you are ready to proceed with the setup.

## 🛠 Setup

### 1. Build & Push the Docker Image

The Docker image is built and pushed to ECR automatically when you push to the `main` branch via **GitHub Actions**.

### 2. Deploy to EKS
```bash
./ai-on-eks-cluster.sh deploy k8s/gpu-deployment.yaml
```

Get external hostname and open in browser:
```bash
echo "http://$(kubectl get svc ai-image-generator-gpu-svc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Click the URL above and try:
👉 "A kubestronaut riding a dragon in space"

**Note:** It might take a few minutes to load the model on first use due to the model size (~8GB), GPU initialization, CUDA kernels warm-up, and cold start on EKS.

### 3. Optional: CPU Deployment
If you don't have GPU nodes, you can use the CPU-based deployment:
```bash
./ai-on-eks-cluster.sh deploy k8s/deployment.yaml
```

Get external hostname and open in browser:
```bash
echo "http://$(kubectl get svc ai-image-generator-svc -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

## 🌍 Demo Ideas
- Show scaling with:
```bash
# For GPU deployment
kubectl scale deployment ai-image-generator-gpu --replicas=2

# For CPU deployment
kubectl scale deployment ai-image-generator-cpu --replicas=2
```
- Run multiple prompts at once to see Kubernetes distribute load.

## 🔗 How They Work Together

Imagine you are building an AI Image Generator:

1. **Streamlit** creates a text box where the user types "A cat in space."
2. **Huggingface-hub** fetches the "Stable Diffusion" model files from the cloud.
3. **Accelerate** loads those files onto your GPU efficiently.
4. **Diffusers** processes the prompt and generates the image pixels.
5. **Streamlit** displays the final image on the webpage.

## 🛠 Tech Stack

**🤖 AI/ML:**
- **Stable Diffusion XL** - AI image generation models
- **PyTorch** - Deep learning framework with CUDA support
- **Diffusers** - Hugging Face library for diffusion models
- **Transformers** - Text encoding and model management

**🖥️ Frontend:**
- **Streamlit** - Python web app framework for UI

**☁️ Cloud Infrastructure:**
- **Amazon EKS** - Managed Kubernetes service
- **NVIDIA T4 GPUs** (g4dn instances) - Hardware acceleration for AI inference
- **Amazon ECR** - Container image storage

**🐳 Containerization:**
- **Python 3.10** - Runtime environment
- **CUDA 11.8** - GPU computing platform

**⚙️ DevOps:**
- **GitHub Actions** - CI/CD pipeline
- **Kubernetes** - Container orchestration
- **kubectl** - Kubernetes CLI tool
- **eksctl** - Amazon EKS CLI
- **AWS CLI** - Amazon Web Services CLI

**🔧 Development:**
- **Bash scripting** - Cluster management automation
- **YAML** - Kubernetes configuration
- **Threading** - Concurrent request handling

## 🧹 Cleanup

When you're done, delete all resources to avoid ongoing AWS charges.

**Delete the EKS clusters:**

```bash
./ai-on-eks-cluster.sh stop
```

This deletes both the CPU cluster (`ai-on-eks-image-cluster`) and the GPU cluster (`ai-on-eks-image-cluster-gpu`) if they exist, including their node groups and associated CloudFormation stacks.

**Delete the ECR repository:**

```bash
aws ecr delete-repository \
  --repository-name ai-image-generator \
  --region $(aws configure get region) \
  --force
```

> The `--force` flag removes all images inside the repository before deleting it.

---

## Join the KSUG.AI Global Community
📍 **250,000+ professionals Around the World!**

📢 **Follow Us:** [https://github.com/ksug-ai](https://github.com/ksug-ai)

🌐 **Website:** [https://ksug.ai](https://ksug.ai/?ref=github)
