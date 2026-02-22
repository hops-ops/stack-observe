# stack-observe

A single Crossplane resource that deploys a complete, production-wired observability stack: metrics, logs, traces, cost monitoring, and Grafana dashboards — all pre-integrated.

## Why Observe?

**Without Observe:**
- 5+ Helm charts to install, configure, and maintain independently
- Cross-component wiring is manual and error-prone (wrong URLs, wrong ports, missing datasources)
- No deletion ordering — removing Prometheus before k8s-monitoring breaks metric collection silently
- Grafana datasources configured by hand, often missing trace-to-log correlation
- Upgrading one chart risks breaking integration with the others

**With Observe:**
- One resource, one API surface, all five components wired together automatically
- Grafana datasources pre-configured with full trace-to-log and trace-to-metric correlation
- Safe deletion ordering enforced via Usage resources (7 dependency edges)
- Cross-component URLs derived from release names — rename a component and everything adjusts
- Override any chart value while keeping cross-component defaults intact

## What Gets Deployed

```
                  ┌─────────────────────────────────────┐
                  │            Observe XR                │
                  └──────────────┬──────────────────────┘
                                 │
         ┌──────────┬────────────┼────────────┬──────────────┐
         ▼          ▼            ▼            ▼              ▼
   ┌──────────┐ ┌──────┐  ┌──────────┐ ┌───────────┐ ┌────────────┐
   │kube-prom │ │ Loki │  │  Tempo   │ │k8s-monitor│ │  Grafana   │
   │  -stack  │ │      │  │          │ │   -ing    │ │  Operator  │
   │(metrics) │ │(logs)│  │ (traces) │ │(collection│ │  (CRDs)    │
   └──────────┘ └──────┘  └──────────┘ │+ OpenCost)│ └────────────┘
                                       └───────────┘
                                             │
                  ┌──────────────────────────┘
                  ▼
   ┌──────────────────────────────────────────────┐
   │  Grafana CR + 3 Datasource CRs              │
   │  (Prometheus, Loki, Tempo — with correlation)│
   └──────────────────────────────────────────────┘
```

**16 composed resources:** 5 Helm Releases + 4 Kubernetes Objects + 7 Usage protections

| Component | Chart | Version | Purpose |
|-----------|-------|---------|---------|
| kube-prometheus-stack | prometheus-community | 82.2.0 | Prometheus, AlertManager, Grafana |
| loki | grafana | 6.53.0 | Log aggregation (SingleBinary default) |
| tempo | grafana | 1.24.4 | Distributed tracing (OTLP, Jaeger, Zipkin) |
| k8s-monitoring | grafana | 3.8.0 | Collection via Alloy + OpenCost |
| grafana-operator | grafana (OCI) | 5.21.4 | Grafana CRD management |

## The Journey

### Stage 1: Getting Started

One field required. Everything else has sensible defaults.

```yaml
apiVersion: stacks.hops.ops.com.ai/v1alpha1
kind: Observe
metadata:
  name: observe
  namespace: default
spec:
  clusterName: my-cluster
```

This deploys all 5 components into the `monitoring` namespace with:
- Prometheus scraping all ServiceMonitors/PodMonitors cluster-wide
- Loki in SingleBinary mode with filesystem storage
- Tempo accepting OTLP, Jaeger, and Zipkin traces
- k8s-monitoring collecting cluster metrics, pod logs, events, and cost data via OpenCost
- Grafana with Loki/Tempo datasources pre-wired (including trace-to-log correlation)

### Stage 2: Customizing for Your Team

Add labels, tune Grafana, adjust component settings.

```yaml
apiVersion: stacks.hops.ops.com.ai/v1alpha1
kind: Observe
metadata:
  name: observe
  namespace: default
spec:
  clusterName: production-cluster
  namespace: monitoring
  labels:
    team: platform
  kubePrometheusStack:
    values:
      grafana:
        adminPassword: changeme
      prometheus:
        prometheusSpec:
          retention: 30d
          storageSpec:
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: 50Gi
  loki:
    values:
      loki:
        storage:
          type: s3
          s3:
            bucketnames: my-loki-bucket
            region: us-east-1
  k8sMonitoring:
    values:
      nodeExporter:
        enabled: false
```

### Stage 3: Local Development

For Colima/kind/minikube — use `default` provider configs instead of cluster-named ones.

```yaml
apiVersion: stacks.hops.ops.com.ai/v1alpha1
kind: Observe
metadata:
  name: observe
  namespace: default
spec:
  clusterName: local
  helmProviderConfigRef:
    name: default
  kubernetesProviderConfigRef:
    name: default
  kubePrometheusStack:
    values:
      grafana:
        adminPassword: local
```

### Stage 4: Full Override

When you need complete control over a component's Helm values (bypassing all defaults):

```yaml
spec:
  kubePrometheusStack:
    overrideAllValues:
      grafana:
        enabled: false
      prometheus:
        prometheusSpec:
          remoteWrite:
            - url: https://mimir.example.com/api/v1/push
```

`overrideAllValues` replaces **all** defaults for that component — chart defaults, cross-component wiring, everything. Use `values` for additive changes instead.

## Cross-Component Wiring

These integrations happen automatically:

| From | To | What |
|------|----|------|
| Grafana | Loki | Datasource with `derivedFields` for trace ID extraction |
| Grafana | Tempo | Datasource with `tracesToLogsV2`, `serviceMap`, `nodeGraph` |
| Grafana | Prometheus | Default datasource |
| Tempo | Prometheus | Metrics generator remote-write |
| k8s-monitoring | Prometheus | Metrics push via `/api/v1/write` |
| k8s-monitoring | Loki | Logs push via gateway `/loki/api/v1/push` |
| k8s-monitoring | Tempo | Traces push via OTLP gRPC `:4317` |
| OpenCost | Prometheus | Cost queries via `/api/v1/query` (OpenCost appends this path) |

## Deletion Ordering

Usage resources enforce safe teardown:

```
datasource-prometheus ─┐
datasource-loki ───────┤─→ grafana-instance ─→ grafana-operator ─→ kube-prometheus-stack
datasource-tempo ──────┘
                                               k8s-monitoring ───→ kube-prometheus-stack
                                               k8s-monitoring ───→ loki
                                               k8s-monitoring ───→ tempo
```

Dependents are deleted before the resources they depend on.

## Sending Traces

Applications send traces to the Alloy receiver:

| Protocol | Endpoint |
|----------|----------|
| OTLP gRPC | `k8s-monitoring-alloy-receiver.monitoring:4317` |
| OTLP HTTP | `k8s-monitoring-alloy-receiver.monitoring:4318` |

Or directly to Tempo:

| Protocol | Endpoint |
|----------|----------|
| OTLP gRPC | `tempo.monitoring:4317` |
| OTLP HTTP | `tempo.monitoring:4318` |
| Jaeger gRPC | `tempo.monitoring:14250` |
| Zipkin | `tempo.monitoring:9411` |

## Spec Reference

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `clusterName` | string | yes | — | Target cluster name; defaults provider config refs |
| `namespace` | string | no | `monitoring` | Shared namespace for all components |
| `labels` | map | no | `{}` | Custom labels merged with defaults |
| `managementPolicies` | []string | no | `["*"]` | Crossplane management policies |
| `helmProviderConfigRef.name` | string | no | `clusterName` | Helm ProviderConfig name |
| `helmProviderConfigRef.kind` | string | no | `ProviderConfig` | `ProviderConfig` or `ClusterProviderConfig` |
| `kubernetesProviderConfigRef.name` | string | no | `clusterName` | Kubernetes ProviderConfig name |
| `kubernetesProviderConfigRef.kind` | string | no | `ProviderConfig` | `ProviderConfig` or `ClusterProviderConfig` |
| `<component>.name` | string | no | chart name | Helm release name |
| `<component>.namespace` | string | no | `namespace` | Per-component namespace override |
| `<component>.values` | object | no | `{}` | Helm values merged with defaults |
| `<component>.overrideAllValues` | object | no | `{}` | Helm values replacing all defaults |

Components: `kubePrometheusStack`, `loki`, `tempo`, `k8sMonitoring`, `grafanaOperator`

## Status

| Field | Type | Description |
|-------|------|-------------|
| `status.ready` | boolean | `true` when all composed resources report Ready |

## Dependencies

| Kind | Package | Version |
|------|---------|---------|
| Function | crossplane-contrib/function-auto-ready | >=v0.6.0 |
| Provider | crossplane-contrib/provider-kubernetes | >=v1 |
| Provider | crossplane-contrib/provider-helm | >=v1 |

## Development

```bash
make render          # Render all examples
make render:minimal  # Render a single example
make validate        # Validate all rendered output
make test            # Run KCL unit tests (11 tests)
make e2e             # Run E2E tests against a live cluster
make build           # Build the Crossplane package
make publish tag=v1  # Build and push to registry
```

## License

Apache-2.0
