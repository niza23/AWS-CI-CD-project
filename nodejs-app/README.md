# nodejs-cicd-app

A production-grade Node.js REST API demonstrating a complete **Jenkins CI + AWS EKS + ArgoCD GitOps** pipeline — built for DevOps/CloudOps portfolio and interviews.

---

## Architecture Overview

```
Developer → GitHub Push
         → Jenkins CI (test → build → scan → push to ECR)
         → Update K8s manifest repo
         → ArgoCD detects drift → syncs to EKS
         → App live on AWS ALB
```

---

## Repo Structure

```
nodejs-app/              ← THIS REPO (application code)
├── src/
│   ├── index.js         ← Express app entry point
│   └── index.test.js    ← Jest unit tests
├── Dockerfile           ← Multi-stage Docker build
├── Jenkinsfile          ← Full CI pipeline (7 stages)
├── package.json
└── .dockerignore

nodejs-k8s-manifests/    ← SEPARATE REPO (GitOps manifests)
├── dev/                 ← Dev namespace K8s manifests
├── prod/                ← Prod namespace K8s manifests
├── argocd/              ← ArgoCD Application & Project CRDs
├── monitoring/          ← Prometheus ServiceMonitor + Grafana dashboard
└── jenkins/             ← Setup scripts for Jenkins EC2 + EKS cluster
```

---

## Jenkins Pipeline Stages

| Stage | What it does |
|---|---|
| Checkout | Clone app repo |
| Install Dependencies | `npm ci` |
| Run Tests | Jest + coverage report |
| SonarQube Analysis | Code quality gate (main branch only) |
| Docker Build | Multi-stage build with non-root user |
| Trivy Scan | HIGH/CRITICAL vulnerability check |
| Push to ECR | Tag with build number, push to AWS ECR |
| Update K8s Manifest (Dev) | Auto-update dev image tag, commit to manifest repo |
| Promote to Prod? | Manual approval gate |
| Update K8s Manifest (Prod) | Update prod image tag after approval |

---

## Prerequisites

- AWS account with IAM permissions for EKS, ECR, IAM
- EC2 instance for Jenkins (t3.medium recommended, Ubuntu 22.04)
- `eksctl`, `kubectl`, `helm` installed locally
- GitHub account (2 repos: this app repo + manifest repo)

---

## Quick Start

### 1. Set up Jenkins EC2

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@<EC2_IP>

# Run the setup script
sudo bash jenkins/jenkins-setup.sh
```

### 2. Create EKS Cluster + Install ArgoCD

```bash
# From your local machine (with AWS CLI configured)
bash jenkins/eks-setup.sh
```

### 3. Configure Jenkins Credentials

In Jenkins UI → Manage Jenkins → Credentials → Add:

| Credential ID | Type | Value |
|---|---|---|
| `aws-credentials` | AWS Credentials | Your IAM Access Key + Secret |
| `ECR_REGISTRY` | Secret text | `<account_id>.dkr.ecr.ap-south-1.amazonaws.com` |
| `github-token` | Username/Password | GitHub username + Personal Access Token |

### 4. Create Jenkins Pipeline Job

1. New Item → Pipeline
2. Pipeline Definition: **Pipeline script from SCM**
3. SCM: Git → URL: `https://github.com/YOUR_USERNAME/nodejs-cicd-app`
4. Script Path: `Jenkinsfile`
5. Build Triggers: **GitHub hook trigger for GITScm polling**

### 5. Apply ArgoCD Resources

```bash
# Update YOUR_USERNAME in these files first!
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml
```

### 6. Apply Namespaces and Initial Manifests

```bash
kubectl apply -f dev/namespace.yaml
kubectl apply -f prod/namespace-hpa.yaml
```

---

## Local Development

```bash
cd nodejs-app
npm install
npm run dev        # starts on port 3000 with nodemon
npm test           # run Jest tests

# Build and run with Docker
docker build -t nodejs-cicd-app:local .
docker run -p 3000:3000 nodejs-cicd-app:local
```

API endpoints:
- `GET /`          → App info
- `GET /health`    → Liveness probe
- `GET /ready`     → Readiness probe
- `GET /api/users` → Sample data endpoint

---

## GitOps Flow (ArgoCD)

1. Jenkins builds image → pushes to ECR → commits new image tag to `nodejs-k8s-manifests` repo
2. ArgoCD polls the manifest repo every 3 minutes (or instantly via webhook)
3. ArgoCD detects drift between Git state and live cluster
4. **Dev**: ArgoCD auto-syncs (automated sync policy)
5. **Prod**: ArgoCD shows drift — requires manual sync click in UI (or `argocd app sync nodejs-cicd-app-prod`)

---

## Monitoring

```bash
# Port-forward Grafana locally
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring

# Open http://localhost:3001
# Username: admin | Password: admin123
```

The `monitoring/grafana/dashboard-configmap.yaml` auto-provisions a dashboard with:
- HTTP requests/sec per namespace
- Pod CPU and memory usage
- Replica count (dev vs prod)

---

## Key DevOps Concepts Demonstrated

- **CI/CD pipeline** — multi-stage Jenkins pipeline with quality gates
- **GitOps** — Git as single source of truth; pull-based deployments via ArgoCD
- **Image immutability** — every build gets a unique tag (build number); `latest` never used in manifests
- **Security** — Trivy scanning, non-root containers, read-only root filesystem, IRSA
- **High availability** — HPA, topology spread constraints, rolling updates with zero downtime
- **Multi-environment** — separate dev/prod namespaces with different sync policies
- **Observability** — Prometheus + Grafana with custom dashboards

---

## Useful Commands

```bash
# Check ArgoCD app status
argocd app list
argocd app get nodejs-cicd-app-dev
argocd app sync nodejs-cicd-app-prod   # manual prod sync

# Watch rollout
kubectl rollout status deployment/nodejs-cicd-app -n dev
kubectl rollout history deployment/nodejs-cicd-app -n prod

# Rollback (ArgoCD)
argocd app rollback nodejs-cicd-app-dev

# View pods
kubectl get pods -n dev -w
kubectl logs -f deployment/nodejs-cicd-app -n dev
```

---

## Author

Built as a DevOps/CloudOps portfolio project demonstrating end-to-end CI/CD with Jenkins, AWS EKS, and ArgoCD GitOps.
