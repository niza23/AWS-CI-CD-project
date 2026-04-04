# nodejs-eks-cicd-gitops

> **Production-grade CI/CD pipeline** for a Node.js app using Jenkins, AWS EKS, ArgoCD GitOps, Docker, and Prometheus — built for DevOps/CloudOps portfolio.

---

## 🗂️ Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Pipeline Stages](#pipeline-stages)
- [GitOps Flow](#gitops-flow)
- [AWS EKS Setup](#aws-eks-setup)
- [Quick Start](#quick-start)
- [Monitoring](#monitoring)
- [Key DevOps Concepts](#key-devops-concepts)
- [Project Highlights](#project-highlights)

---

## Overview

A complete, end-to-end automated DevOps project where a single `git push` triggers the full pipeline — from code to live production — with **zero manual intervention**.

```
Developer  →  git push  →  Jenkins CI  →  Docker Image  →  AWS ECR
                                                                 ↓
Users  ←  AWS ALB  ←  AWS EKS  ←  ArgoCD deploys  ←  Manifest repo updated
```

### What makes this project production-ready?

| Feature | Implementation |
|---|---|
| Automated testing | Jest unit tests + coverage report |
| Code quality gate | SonarQube analysis on every main branch push |
| Security scanning | Trivy scans Docker image for CVEs before push |
| Zero-downtime deploy | Kubernetes Rolling Update (maxUnavailable: 0) |
| GitOps / Self-healing | ArgoCD reconciles cluster to Git state continuously |
| Auto-scaling | HPA scales pods based on CPU/memory usage |
| Observability | Prometheus + Grafana with custom dashboards |
| Security hardening | Non-root container, read-only filesystem, IRSA (no static AWS keys) |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DEVELOPER                                │
│                       git push                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │ webhook
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                     JENKINS CI (EC2)                            │
│  Checkout → Install → Test → SonarQube → Docker Build →        │
│  Trivy Scan → Push to ECR → Update Manifest Repo               │
└──────────────────────────┬──────────────────────────────────────┘
                           │ git commit (image tag update)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│               GITHUB — nodejs-k8s-manifests repo                │
│         dev/deployment.yaml  |  prod/deployment.yaml           │
└──────────────────────────┬──────────────────────────────────────┘
                           │ ArgoCD polls every 3 min
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AWS EKS CLUSTER                            │
│                                                                 │
│  ┌─────────────────────┐    ┌──────────────────────────────┐   │
│  │   Namespace: dev    │    │      Namespace: prod         │   │
│  │  2 pods (HPA: 2-5) │    │   3 pods (HPA: 3-10)        │   │
│  │  auto-sync ON       │    │   manual sync (approval)     │   │
│  └─────────────────────┘    └──────────────────────────────┘   │
│                                                                 │
│  ArgoCD  |  Prometheus  |  Grafana  |  ALB Ingress Controller  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Application | Node.js 20 + Express.js |
| Containerization | Docker (multi-stage build) |
| CI Server | Jenkins (on AWS EC2) |
| Image Registry | AWS ECR (Elastic Container Registry) |
| Container Orchestration | AWS EKS (Elastic Kubernetes Service) |
| GitOps / CD | ArgoCD |
| Ingress | AWS ALB Ingress Controller |
| Auto-scaling | Kubernetes HPA |
| Code Quality | SonarQube |
| Security Scan | Trivy |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) |
| IAM Auth | IRSA (IAM Roles for Service Accounts) |
| Infra Setup | eksctl + Helm |

---

## Repository Structure

This project uses **two separate GitHub repositories** — a core GitOps pattern:

```
Repo 1: nodejs-cicd-app          ← Application source code (this repo)
Repo 2: nodejs-k8s-manifests     ← Kubernetes deployment manifests (GitOps)
```

### Repo 1 — Application (this repo)

```
nodejs-cicd-app/
├── src/
│   ├── index.js              # Express app (/, /health, /ready, /api/users)
│   └── index.test.js         # Jest unit tests
├── Dockerfile                # Multi-stage Docker build
├── Jenkinsfile               # 7-stage Jenkins declarative pipeline
├── package.json
├── .dockerignore
└── README.md
```

### Repo 2 — K8s Manifests

```
nodejs-k8s-manifests/
├── dev/
│   ├── namespace.yaml        # Namespace + ServiceAccount (IRSA)
│   ├── deployment.yaml       # 2 replicas — image tag auto-updated by Jenkins
│   ├── service.yaml          # ClusterIP service
│   ├── ingress.yaml          # AWS ALB Ingress (HTTP)
│   └── hpa.yaml              # HPA: 2–5 pods at 70% CPU
├── prod/
│   ├── namespace-hpa.yaml    # Namespace + ServiceAccount + HPA (3–10 pods)
│   ├── deployment.yaml       # 3 replicas — promoted after manual approval
│   ├── service.yaml          # ClusterIP service
│   └── ingress.yaml          # AWS ALB Ingress (HTTPS + ACM)
├── argocd/
│   ├── project.yaml          # ArgoCD AppProject (security boundary)
│   ├── app-dev.yaml          # ArgoCD Application: dev (auto-sync ON)
│   └── app-prod.yaml         # ArgoCD Application: prod (manual sync)
├── monitoring/
│   ├── prometheus/
│   │   └── servicemonitor.yaml
│   └── grafana/
│       └── dashboard-configmap.yaml
└── jenkins/
    ├── jenkins-setup.sh      # Jenkins EC2 install script
    └── eks-setup.sh          # EKS + ArgoCD + ALB Controller setup
```

---

## Pipeline Stages

The `Jenkinsfile` defines a 7-stage declarative pipeline. Each stage is a quality gate — if any stage fails, the pipeline stops immediately.

```
Stage 1 → Checkout          Clone repo at the triggering commit
Stage 2 → Install + Test    npm ci + Jest unit tests + coverage
Stage 3 → SonarQube         Code quality gate (main branch only)
Stage 4 → Docker Build      Multi-stage build — non-root user, minimal image
Stage 5 → Trivy Scan        Block HIGH/CRITICAL CVEs before push
Stage 6 → Push to ECR       Tag with build number, push to AWS ECR
Stage 7 → Update Manifest   sed image tag in manifest repo + git commit
         → Manual Gate       input: "Deploy to Production?" (prod only)
         → Update Prod       Update prod/deployment.yaml after approval
```

### Key pipeline design decisions

- `npm ci` (not `npm install`) — reproducible, lockfile-exact installs
- Multi-stage Docker — test tools never ship to production (~120MB vs ~280MB)
- `[skip ci]` in commit message — prevents infinite loop when Jenkins commits to manifest repo
- `disableConcurrentBuilds()` — only one build at a time per job
- `timeout(30, MINUTES)` — stuck pipelines don't block the queue

---

## GitOps Flow

```
Jenkins commits new image tag → manifest repo
          ↓
ArgoCD polls repo every 3 min → detects diff
          ↓
dev:  auto-sync immediately
prod: shows OutOfSync → human reviews diff → clicks Sync in ArgoCD UI
          ↓
Kubernetes rolling update (maxUnavailable: 0 → zero downtime)
          ↓
New pods pass readiness probe → old pods terminate
```

### ArgoCD sync policies

| Environment | Sync Mode | prune | selfHeal | Min Replicas |
|---|---|---|---|---|
| dev | Automated | ✅ | ✅ | 2 |
| prod | Manual | — | — | 3 |

### Rollback

```bash
# Option 1 — GitOps way (preferred, full audit trail)
git revert HEAD   # in manifest repo
git push          # ArgoCD auto-syncs back to previous image

# Option 2 — ArgoCD UI
# App → History and Rollback → select previous sync → Rollback

# Option 3 — CLI
argocd app rollback nodejs-cicd-app-dev
```

---

## AWS EKS Setup

### Prerequisites

- AWS CLI configured with appropriate IAM permissions
- `eksctl`, `kubectl`, `helm` installed locally
- GitHub account (2 repos created)
- EC2 instance for Jenkins (t3.medium, Ubuntu 22.04)

### 1. Set up Jenkins on EC2

```bash
ssh -i your-key.pem ubuntu@<EC2_PUBLIC_IP>
sudo bash jenkins/jenkins-setup.sh
```

This installs: Jenkins, Java 17, Docker, AWS CLI v2, kubectl, Trivy.

### 2. Create EKS Cluster + Install ArgoCD

```bash
bash jenkins/eks-setup.sh
```

This creates: EKS cluster (t3.medium nodes), AWS Load Balancer Controller, ArgoCD, Prometheus + Grafana stack, ECR repository.

### 3. Configure Jenkins Credentials

In Jenkins UI → Manage Jenkins → Credentials → Global → Add Credential:

| Credential ID | Type | Value |
|---|---|---|
| `aws-credentials` | AWS Credentials | IAM Access Key + Secret Key |
| `ECR_REGISTRY` | Secret text | `<account_id>.dkr.ecr.ap-south-1.amazonaws.com` |
| `github-token` | Username + Password | GitHub username + Personal Access Token |

### 4. Create Jenkins Pipeline Job

1. New Item → Pipeline
2. Pipeline from SCM → Git → URL: `https://github.com/YOUR_USERNAME/nodejs-cicd-app`
3. Script Path: `Jenkinsfile`
4. Build Triggers: GitHub hook trigger for GITScm polling

### 5. Apply ArgoCD Resources

```bash
# Update YOUR_USERNAME in argocd/*.yaml first
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml

# Apply namespaces
kubectl apply -f dev/namespace.yaml
kubectl apply -f prod/namespace-hpa.yaml
```

---

## Local Development

```bash
cd nodejs-cicd-app
npm install
npm run dev          # starts on :3000 with nodemon
npm test             # Jest tests + coverage

# Docker
docker build -t nodejs-cicd-app:local .
docker run -p 3000:3000 nodejs-cicd-app:local
```

### API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/` | App info, version, environment |
| GET | `/health` | Liveness probe |
| GET | `/ready` | Readiness probe |
| GET | `/api/users` | Sample data endpoint |

---

## Monitoring

```bash
# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring
# open http://localhost:3001  →  admin / admin123

# ArgoCD UI
kubectl port-forward svc/argocd-server 8080:443 -n argocd
# open http://localhost:8080
```

### Grafana Dashboard covers

- HTTP requests/sec by namespace, method, status code
- Pod CPU usage per pod
- Pod memory usage per pod
- Replica count — actual vs desired

---

## Key DevOps Concepts

| Concept | Where it's demonstrated |
|---|---|
| CI/CD Pipeline | Jenkinsfile — 7 stages from test to deploy |
| GitOps | ArgoCD watches manifest repo, Git = source of truth |
| Push vs Pull CD | Jenkins pushes to ECR; ArgoCD pulls from GitHub |
| Image Immutability | Every build = unique tag (build number), never use `:latest` in manifests |
| Zero-downtime Deploy | Rolling update with `maxUnavailable: 0` + readiness probes |
| Self-healing | ArgoCD reverts any manual cluster changes back to Git state |
| Auto-scaling | HPA scales pods on CPU/memory threshold |
| Secrets Management | IRSA — no static AWS keys anywhere, temporary credentials via OIDC |
| Multi-environment | Dev (auto-sync) and Prod (manual gate) with separate namespaces |
| Security Hardening | Non-root user, read-only filesystem, Trivy CVE scanning |
| Observability | Prometheus scraping + Grafana auto-provisioned dashboard |
| Audit Trail | Every deployment = a Git commit in manifest repo |

---

## Project Highlights

- **Two-repo GitOps pattern** — app code and deployment config separated for clean access control and independent rollbacks
- **Manual approval gate** — production deployments require explicit human approval via Jenkins `input` step
- **HPA + ArgoCD coexistence** — `ignoreDifferences` on `/spec/replicas` prevents ArgoCD from fighting the autoscaler
- **`[skip ci]` pattern** — prevents infinite loop when Jenkins commits to the manifest repo
- **IRSA over static keys** — pods authenticate to AWS via OIDC token exchange, credentials rotate every hour

---

## Author

Built as a DevOps/CloudOps portfolio project demonstrating end-to-end CI/CD with Jenkins, AWS EKS, and ArgoCD GitOps.

---

## License

MIT
