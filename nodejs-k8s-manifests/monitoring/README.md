# monitoring/

Observability configuration for the Node.js app running in EKS. Uses the **kube-prometheus-stack** Helm chart which bundles Prometheus, Grafana, AlertManager, and all Kubernetes metric exporters in one install.

---

## Subfolders

| Folder | Purpose |
|---|---|
| `prometheus/` | ServiceMonitor — tells Prometheus which pods to scrape |
| `grafana/` | Dashboard ConfigMap — auto-provisions Grafana dashboard |

---

## How monitoring works in this project

```
Node.js pods expose /metrics endpoint
        ↓
Prometheus ServiceMonitor tells Prometheus: "scrape these pods every 30s"
        ↓
Prometheus stores time-series metrics data
        ↓
Grafana reads from Prometheus → displays dashboards
        ↓
You see: requests/sec, CPU, memory, replica count — all live
```

---

## Install kube-prometheus-stack (one time)

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install the full stack into monitoring namespace
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

The flag `serviceMonitorSelectorNilUsesHelmValues=false` is important — without it, Prometheus only scrapes ServiceMonitors that have the same Helm release label. With it, Prometheus scrapes ALL ServiceMonitors in the cluster including ours.

---

## Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3001:80 -n monitoring
```

Open: http://localhost:3001
- Username: `admin`
- Password: `admin123`

---

## Access Prometheus

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
```

Open: http://localhost:9090

---

## Apply monitoring configs

```bash
kubectl apply -f monitoring/prometheus/servicemonitor.yaml
kubectl apply -f monitoring/grafana/dashboard-configmap.yaml
```

Grafana auto-detects ConfigMaps with label `grafana_dashboard: "1"` and imports the dashboard automatically — no manual clicking in Grafana UI needed.

