# nodejs-k8s-manifests

GitOps manifest repository for the **nodejs-cicd-app** project. This repo is the single source of truth for Kubernetes deployments — managed by **ArgoCD** running on AWS EKS.

> Jenkins CI writes to this repo. ArgoCD reads from it. You never `kubectl apply` manually in production.

---

## Structure

```
nodejs-k8s-manifests/
├── dev/
│   ├── namespace.yaml       ← Namespace + ServiceAccount (IRSA)
│   ├── deployment.yaml      ← Deployment (image tag updated by Jenkins)
│   ├── service.yaml         ← ClusterIP Service
│   ├── ingress.yaml         ← AWS ALB Ingress
│   └── hpa.yaml             ← HorizontalPodAutoscaler (2–5 replicas)
├── prod/
│   ├── namespace-hpa.yaml   ← Namespace + ServiceAccount + HPA (3–10 replicas)
│   ├── deployment.yaml      ← Deployment (promoted by Jenkins after approval)
│   ├── service.yaml         ← ClusterIP Service
│   └── ingress.yaml         ← AWS ALB Ingress with HTTPS/ACM
├── argocd/
│   ├── project.yaml         ← ArgoCD AppProject (source + dest restrictions)
│   ├── app-dev.yaml         ← ArgoCD Application: dev (auto-sync ON)
│   └── app-prod.yaml        ← ArgoCD Application: prod (manual sync)
├── monitoring/
│   ├── prometheus/
│   │   └── servicemonitor.yaml  ← Prometheus ServiceMonitor for both namespaces
│   └── grafana/
│       └── dashboard-configmap.yaml ← Auto-provisioned Grafana dashboard
└── jenkins/
    ├── jenkins-setup.sh     ← Jenkins EC2 install script
    └── eks-setup.sh         ← EKS + ArgoCD + ALB Controller setup script
```

---

## How the GitOps Loop Works

```
Jenkins CI (on every build)
  └─► docker push → ECR
  └─► sed image tag in dev/deployment.yaml
  └─► git commit + push → this repo

ArgoCD (polling every 3 min)
  └─► detects diff between Git and live cluster
  └─► dev:  auto-syncs immediately
  └─► prod: marks OutOfSync, waits for manual approval
```

---

## Sync Policies

| Environment | Sync Mode | Prune | Self-Heal |
|---|---|---|---|
| dev | Automated | ✅ | ✅ |
| prod | Manual | — | — |

Prod uses manual sync intentionally — changes are verified in dev first, then promoted via Jenkins approval gate.

---

## Setup

See `jenkins/eks-setup.sh` for full cluster + ArgoCD installation.

```bash
# Apply ArgoCD resources (one-time)
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/app-dev.yaml
kubectl apply -f argocd/app-prod.yaml

# Apply namespaces (one-time)
kubectl apply -f dev/namespace.yaml
kubectl apply -f prod/namespace-hpa.yaml
```

After initial setup, all subsequent deployments happen automatically through the GitOps loop.
