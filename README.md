# 🎨 AI Image Generator on EKS by [KSUG.AI](https://ksug.ai)

This is a hands-on workshop python app that runs **Stable Diffusion** on **Amazon Elastic Kubernetes Service (EKS)**.

## 🚀 Features
- Generate AI images from text prompts
- Runs on EKS (CPU or GPU nodes)
- Scales with Kubernetes deployments

**Performance:** GPU is recommended, typically an image can be generated in ~30 seconds with NVIDIA T4 (g4dn.xlarge). For CPU, it does take 15 mins or much longer.

## Prerequisites

- AWS CLI configured (`aws configure`)
- `eksctl` installed
- `kubectl` installed
- For GPU clusters: your account needs a vCPU quota of at least 4 for G and VT instances. Check with:
  ```bash
  aws service-quotas get-service-quota --region $(aws configure get region) \
    --service-code ec2 --quota-code L-DB2E81BA \
    --query "Quota.Value" --output text
  ```
  If the value is 0, request an increase:
  ```bash
  aws service-quotas request-service-quota-increase \
    --region $(aws configure get region) \
    --service-code ec2 --quota-code L-DB2E81BA \
    --desired-value 4
  ```
  Approval may take a few minutes to a couple of days. The script will verify this automatically before creating a GPU cluster.

Create an EKS cluster with GPU nodes using the provided script:

```bash
./ai-on-eks-cluster.sh gpu
```

**Optional: Create a CPU-based EKS cluster:**
```bash
./ai-on-eks-cluster.sh cpu
```
Once the cluster is created, you are ready to proceed with the setup.

## 🛠 Setup

### 1. Build & Push the Docker Image
```bash
./ai-on-eks-cluster.sh build
```
This creates the ECR repository (if needed), builds the Docker image, and pushes it.

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

### 4. Optional: Build with a Custom Tag
```bash
./ai-on-eks-cluster.sh build v1.0
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
- **Docker** - Application containerization
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

## Join the KSUG.AI Global Community
📍 **Meetups Around the World!**

📢 **Follow Us:** [https://github.com/ksug-ai](https://github.com/ksug-ai)

🌐 **Website:** [https://ksug.ai](https://ksug.ai/?ref=github)
