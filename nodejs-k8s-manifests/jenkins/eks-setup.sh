#!/bin/bash
# ============================================================
# EKS Cluster Setup Script
# Prerequisites: AWS CLI configured, eksctl installed, kubectl installed
# Run: bash eks-setup.sh
# ============================================================
set -euo pipefail

CLUSTER_NAME="nodejs-cicd-cluster"
REGION="ap-south-1"
NODE_TYPE="t3.medium"
MIN_NODES=2
MAX_NODES=4
DESIRED_NODES=2
K8S_VERSION="1.29"

echo "==> [1/6] Creating EKS cluster: ${CLUSTER_NAME}"
eksctl create cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --version "${K8S_VERSION}" \
  --nodegroup-name standard-workers \
  --node-type "${NODE_TYPE}" \
  --nodes "${DESIRED_NODES}" \
  --nodes-min "${MIN_NODES}" \
  --nodes-max "${MAX_NODES}" \
  --managed \
  --with-oidc \
  --full-ecr-access \
  --alb-ingress-access

echo "==> [2/6] Update kubeconfig"
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"
kubectl get nodes

echo "==> [3/6] Install AWS Load Balancer Controller"
# Create IAM policy
curl -fsSL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json \
  -o /tmp/alb-iam-policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/alb-iam-policy.json || echo "Policy may already exist, continuing..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster="${CLUSTER_NAME}" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --approve \
  --override-existing-serviceaccounts

# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo "==> [4/6] Install ArgoCD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "  Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# Patch ArgoCD server to LoadBalancer for easy access
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

echo "==> [5/6] Install Prometheus + Grafana (kube-prometheus-stack)"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false

echo "==> [6/6] Create ECR Repository"
aws ecr create-repository \
  --repository-name nodejs-cicd-app \
  --region "${REGION}" \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256 || echo "ECR repo may already exist."

echo ""
echo "======================================================"
echo " EKS Cluster setup complete!"
echo ""
echo " ArgoCD URL:"
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
echo " ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
echo ""
echo " ECR Registry:"
echo "  ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/nodejs-cicd-app"
echo ""
echo " NEXT STEPS:"
echo "  1. Apply namespaces:  kubectl apply -f dev/namespace.yaml -f prod/namespace-hpa.yaml"
echo "  2. Apply ArgoCD apps: kubectl apply -f argocd/project.yaml -f argocd/app-dev.yaml -f argocd/app-prod.yaml"
echo "  3. Update YOUR_USERNAME in argocd/*.yaml with your GitHub username"
echo "  4. Update ECR registry ARN in dev/namespace.yaml and prod/namespace-hpa.yaml"
echo "======================================================"
