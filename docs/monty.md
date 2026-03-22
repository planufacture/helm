# Kubernetes Cluster Setup — nak.ie

## Cluster Details

| Property | Value |
|----------|-------|
| Platform | MicroK8s on Ubuntu (single node) |
| Kubernetes Version | 1.33 |
| API Endpoint | `https://kubernetes.k8s.nak.ie:16443` |
| CNI | Cilium 1.15.2 |
| Node Name | `monty` |

---

## Networking & DNS

- **Tailscale** is used for private networking — the cluster is not publicly accessible
- **Cloudflare** manages DNS for `nak.ie`
- Wildcard DNS record: `*.k8s.nak.ie` → Tailscale IP `100.83.34.30` (DNS only, no proxy)
- Explicit record: `kubernetes.k8s.nak.ie` → `100.83.34.30` (for API server access)
- All services are accessible only to devices on the Tailscale network

### Service URL Pattern
Every deployed service gets a URL following this pattern:
```
https://<service-name>.k8s.nak.ie
```

---

## Installed Addons

| Addon | Purpose | Status |
|-------|---------|--------|
| Cilium | CNI / networking | ✅ Running |
| Hubble | Cilium observability UI | ✅ Running |
| CoreDNS | Cluster DNS | ✅ Running |
| Ingress (NGINX) | Ingress controller | ✅ Running |
| cert-manager | TLS certificate management | ✅ Running |
| hostpath-storage | Persistent volume storage | ✅ Running |

---

## TLS / cert-manager

Certificates are issued automatically via **Let's Encrypt** using **Cloudflare DNS-01 challenge**.

### ClusterIssuer
Name: `letsencrypt-cloudflare`

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: you@yourdomain.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

### How to Use in an Ingress
Add these annotations and TLS block to any Ingress resource:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare
spec:
  ingressClassName: public
  tls:
  - hosts:
    - myapp.k8s.nak.ie
    secretName: myapp-tls
  rules:
  - host: myapp.k8s.nak.ie
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

cert-manager will automatically issue and renew the certificate.

---

## Helm Deployment

### Ingress Template
Use this pattern in your Helm chart's `ingress.yaml`:

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "chart.fullname" . }}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare
spec:
  ingressClassName: public
  tls:
  - hosts:
    - {{ .Values.ingress.host }}
    secretName: {{ include "chart.fullname" . }}-tls
  rules:
  - host: {{ .Values.ingress.host }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ include "chart.fullname" . }}
            port:
              number: {{ .Values.service.port }}
{{- end }}
```

### values.yaml Pattern
```yaml
ingress:
  enabled: true
  host: myapp.k8s.nak.ie

service:
  type: ClusterIP
  port: 80
```

---

## GitHub Actions Deployment Workflow

The cluster is private (Tailscale only), so GitHub Actions runners need to join the Tailscale network before they can reach the API server.

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `TAILSCALE_AUTHKEY` | Reusable ephemeral auth key from Tailscale admin → Settings → Keys |
| `KUBECONFIG` | Base64 encoded kubeconfig (`cat ~/.kube/config \| base64`) |

### Workflow File `.github/workflows/deploy.yaml`

```yaml
name: Deploy to Kubernetes

on:
  push:
    branches: [main]

env:
  CHART_NAME: your-chart-name        # Name of your Helm chart
  RELEASE_NAME: your-release-name    # Helm release name
  NAMESPACE: default                 # Kubernetes namespace

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Connect to Tailscale
        uses: tailscale/github-action@v2
        with:
          authkey: ${{ secrets.TAILSCALE_AUTHKEY }}

      - name: Setup kubectl
        uses: azure/setup-kubectl@v3

      - name: Setup Helm
        uses: azure/setup-helm@v3

      - name: Configure kubectl
        run: |
          mkdir -p ~/.kube
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > ~/.kube/config
          kubectl config use-context microk8s

      - name: Verify cluster connection
        run: kubectl get nodes

      - name: Deploy via Helm
        run: |
          helm upgrade --install ${{ env.RELEASE_NAME }} ./helm/${{ env.CHART_NAME }} \
            --namespace ${{ env.NAMESPACE }} \
            --create-namespace \
            --wait \
            --timeout 5m \
            -f ./helm/${{ env.CHART_NAME }}/values.yaml

      - name: Verify deployment
        run: |
          kubectl rollout status deployment/${{ env.RELEASE_NAME }} \
            -n ${{ env.NAMESPACE }} \
            --timeout=120s

      - name: Print service URL
        run: |
          kubectl get ingress -n ${{ env.NAMESPACE }}
```

---

## Recommended Helm Project Structure

```
your-project/
├── .github/
│   └── workflows/
│       └── deploy.yaml
├── helm/
│   └── your-chart/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           └── _helpers.tpl
├── src/                      # Your application source
└── CLUSTER.md                # This file
```

---

## Useful kubectl Commands

```bash
# Check all pods
kubectl get pods -A

# Check ingress
kubectl get ingress -A

# Check certificates
kubectl get certificates -A

# Watch certificate issuance
kubectl get certificate -w

# Check Cilium/Hubble status
kubectl exec -n kube-system ds/cilium -- cilium-dbg status

# Port-forward Hubble UI
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Then open http://localhost:12000
```

---

## Notes

- The cluster is single-node — no need for `podAntiAffinity` or replica concerns
- Storage class for PVCs: `microk8s-hostpath`
- Ingress class name: `public`
- ClusterIssuer name: `letsencrypt-cloudflare`
- API server port: `16443` (non-standard — MicroK8s default)