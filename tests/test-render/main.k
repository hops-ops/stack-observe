import models.ai.com.ops.hops.stacks.v1alpha1 as stacksv1alpha1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1
import models.k8s.apimachinery.pkg.apis.meta.v1 as metav1

# ==============================================================================
# Unit tests for Observe XRD
#
# Philosophy: Test YOUR API, not the provider's API.
# - render/validate already checks provider schema correctness
# - Tests should verify XRD spec fields produce expected behavior
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: Minimal input renders all 5 Helm Releases
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "minimal-renders-all-components"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "test-observe"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "kube-prometheus-stack"
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "loki"
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "tempo"
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "k8s-monitoring"
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "grafana-operator"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 2: Custom labels are merged with defaults
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "custom-labels-merged-with-defaults"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "labeled-observe"
                spec = {
                    clusterName = "my-cluster"
                    labels = {team = "platform", environment = "staging"}
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata = {
                        name = "kube-prometheus-stack"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/observe" = "labeled-observe"
                            team = "platform"
                            environment = "staging"
                        }
                    }
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata = {
                        name = "loki"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/observe" = "labeled-observe"
                            team = "platform"
                            environment = "staging"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3: Cross-component defaults wire KPS Grafana datasources to Loki/Tempo
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "kps-cross-component-datasources"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "ds-test"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "kube-prometheus-stack"
                    spec.forProvider.values = {
                        grafana.additionalDataSources = [
                            {
                                name = "Loki"
                                type = "loki"
                                uid = "loki"
                                url = "http://loki-gateway.monitoring:80"
                                access = "proxy"
                                jsonData = {
                                    maxLines = 1000
                                    derivedFields = [
                                        {
                                            name = "TraceID"
                                            matcherRegex = "\"traceId\":\"([a-f0-9]+)\""
                                            url = "$" + "$" + "{__value.raw}"
                                            datasourceUid = "tempo"
                                        }
                                    ]
                                }
                            }
                            {
                                name = "Tempo"
                                type = "tempo"
                                uid = "tempo"
                                url = "http://tempo.monitoring:3200"
                                access = "proxy"
                                jsonData = {
                                    httpMethod = "GET"
                                    tracesToLogsV2 = {
                                        datasourceUid = "loki"
                                        spanStartTimeShift = "-1h"
                                        spanEndTimeShift = "1h"
                                        filterByTraceID = True
                                        filterBySpanID = False
                                    }
                                    tracesToMetrics = {
                                        datasourceUid = "prometheus"
                                        spanStartTimeShift = "-1h"
                                        spanEndTimeShift = "1h"
                                    }
                                    serviceMap.datasourceUid = "prometheus"
                                    nodeGraph.enabled = True
                                    lokiSearch.datasourceUid = "loki"
                                }
                            }
                        ]
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 4: overrideAllValues on KPS replaces all defaults
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "override-all-values-replaces-defaults"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "override-test"
                spec = {
                    clusterName = "my-cluster"
                    kubePrometheusStack = {
                        overrideAllValues = {
                            grafana = {enabled = False}
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "kube-prometheus-stack"
                    spec.forProvider.values = {
                        grafana = {enabled = False}
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 5: Cross-component defaults wire K8sMonitoring destinations
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "k8smon-destinations-wired"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "dest-test"
                spec.clusterName = "my-cluster"
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "k8s-monitoring"
                    spec.forProvider.values = {
                        destinations = [
                            {
                                name = "prometheus"
                                type = "prometheus"
                                url = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"
                            }
                            {
                                name = "loki"
                                type = "loki"
                                url = "http://loki-gateway.monitoring:80/loki/api/v1/push"
                            }
                            {
                                name = "tempo"
                                type = "otlp"
                                url = "http://tempo.monitoring:4317"
                                protocol = "grpc"
                            }
                        ]
                    }
                }
            ]
        }
    }
    # ==========================================================================
    # Test 6: KPS user values at non-conflicting key merge with defaults
    # ==========================================================================
    # User provides prometheus config; cross-component grafana datasources preserved
    metav1alpha1.CompositionTest {
        metadata.name = "kps-nonconflicting-values-merge"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "kps-merge"
                spec = {
                    clusterName = "my-cluster"
                    kubePrometheusStack = {
                        values = {
                            prometheus = {
                                prometheusSpec = {
                                    retention = "30d"
                                }
                            }
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "kube-prometheus-stack"
                    spec.forProvider.values = {
                        grafana.additionalDataSources = [
                            {
                                name = "Loki"
                                type = "loki"
                                uid = "loki"
                                url = "http://loki-gateway.monitoring:80"
                                access = "proxy"
                                jsonData = {
                                    maxLines = 1000
                                    derivedFields = [
                                        {
                                            name = "TraceID"
                                            matcherRegex = "\"traceId\":\"([a-f0-9]+)\""
                                            url = "$" + "$" + "{__value.raw}"
                                            datasourceUid = "tempo"
                                        }
                                    ]
                                }
                            }
                            {
                                name = "Tempo"
                                type = "tempo"
                                uid = "tempo"
                                url = "http://tempo.monitoring:3200"
                                access = "proxy"
                                jsonData = {
                                    httpMethod = "GET"
                                    tracesToLogsV2 = {
                                        datasourceUid = "loki"
                                        spanStartTimeShift = "-1h"
                                        spanEndTimeShift = "1h"
                                        filterByTraceID = True
                                        filterBySpanID = False
                                    }
                                    tracesToMetrics = {
                                        datasourceUid = "prometheus"
                                        spanStartTimeShift = "-1h"
                                        spanEndTimeShift = "1h"
                                    }
                                    serviceMap.datasourceUid = "prometheus"
                                    nodeGraph.enabled = True
                                    lokiSearch.datasourceUid = "loki"
                                }
                            }
                        ]
                        prometheus.prometheusSpec.retention = "30d"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 7: KPS conflicting key (grafana) deep-merges with defaults
    # ==========================================================================
    # mergeOverwrite: user grafana values merge with chart + cross-component defaults
    metav1alpha1.CompositionTest {
        metadata.name = "kps-conflicting-values-deep-merged"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "kps-conflict"
                spec = {
                    clusterName = "my-cluster"
                    kubePrometheusStack = {
                        values = {
                            grafana = {
                                adminPassword = "changeme"
                            }
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "kube-prometheus-stack"
                    spec.forProvider.values = {
                        grafana = {
                            additionalDataSources = [
                                {
                                    name = "Loki"
                                    type = "loki"
                                    uid = "loki"
                                    url = "http://loki-gateway.monitoring:80"
                                    access = "proxy"
                                    jsonData = {
                                        maxLines = 1000
                                        derivedFields = [
                                            {
                                                name = "TraceID"
                                                matcherRegex = "\"traceId\":\"([a-f0-9]+)\""
                                                url = "$" + "$" + "{__value.raw}"
                                                datasourceUid = "tempo"
                                            }
                                        ]
                                    }
                                }
                                {
                                    name = "Tempo"
                                    type = "tempo"
                                    uid = "tempo"
                                    url = "http://tempo.monitoring:3200"
                                    access = "proxy"
                                    jsonData = {
                                        httpMethod = "GET"
                                        tracesToLogsV2 = {
                                            datasourceUid = "loki"
                                            spanStartTimeShift = "-1h"
                                            spanEndTimeShift = "1h"
                                            filterByTraceID = True
                                            filterBySpanID = False
                                        }
                                        tracesToMetrics = {
                                            datasourceUid = "prometheus"
                                            spanStartTimeShift = "-1h"
                                            spanEndTimeShift = "1h"
                                        }
                                        serviceMap.datasourceUid = "prometheus"
                                        nodeGraph.enabled = True
                                        lokiSearch.datasourceUid = "loki"
                                    }
                                }
                            ]
                            adminPassword = "changeme"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 8: K8sMon user values merge alongside destination defaults
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "k8smon-values-merge-with-destinations"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "k8smon-merge"
                spec = {
                    clusterName = "my-cluster"
                    k8sMonitoring = {
                        values = {
                            nodeExporter = {enabled = False}
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "k8s-monitoring"
                    spec.forProvider.values = {
                        destinations = [
                            {
                                name = "prometheus"
                                type = "prometheus"
                                url = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"
                            }
                            {
                                name = "loki"
                                type = "loki"
                                url = "http://loki-gateway.monitoring:80/loki/api/v1/push"
                            }
                            {
                                name = "tempo"
                                type = "otlp"
                                url = "http://tempo.monitoring:4317"
                                protocol = "grpc"
                            }
                        ]
                        nodeExporter.enabled = False
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 9: Tempo user values merge alongside metricsGenerator defaults
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "tempo-values-merge-with-metricsgenerator"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "tempo-merge"
                spec = {
                    clusterName = "my-cluster"
                    tempo = {
                        values = {
                            service = {type = "LoadBalancer"}
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "tempo"
                    spec.forProvider.values = {
                        tempo.metricsGenerator = {
                            enabled = True
                            remoteWriteUrl = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"
                        }
                        service.type = "LoadBalancer"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 10: Loki values merge with defaults
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "loki-values-merge-with-defaults"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "loki-vals"
                spec = {
                    clusterName = "my-cluster"
                    loki = {
                        values = {
                            loki.auth_enabled = False
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "loki"
                    spec.forProvider.values = {
                        deploymentMode = "SingleBinary"
                        loki.auth_enabled = False
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 11: GrafanaOperator user values pass through directly
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "grafana-operator-values-passthrough"
        spec = {
            compositionPath = "apis/observes/composition.yaml"
            xrdPath = "apis/observes/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.Observe {
                metadata.name = "grafop-vals"
                spec = {
                    clusterName = "my-cluster"
                    grafanaOperator = {
                        values = {
                            watchNamespaces = ["monitoring"]
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "grafana-operator"
                    spec.forProvider.values = {
                        watchNamespaces = ["monitoring"]
                    }
                }
            ]
        }
    }
]

items = _items
