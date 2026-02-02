import datetime
import math
import models.ai.com.ops.hops.stacks.v1alpha1 as stacksv1alpha1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# ==============================================================================
# E2E Test for Observe (Kubernetes-only)
#
# All components run in-cluster: Helm releases + provider-kubernetes Objects.
# No cloud credentials needed - uses InjectedIdentity for both providers.
#
# Run: make e2e
# Run without cleanup: up test run tests/e2etest-observe --e2e --skip-control-plane-cleanup
# ==============================================================================

_now = str(int(math.floor(datetime.ticks())))
_test_name = "e2e-obs-" + _now

_items = [
    metav1alpha1.E2ETest {
        metadata.name = "observe-e2e"
        spec = {
            crossplane = {
                autoUpgrade.channel = "Rapid"
            }
            defaultConditions = ["Ready"]
            timeoutSeconds = 3600  # 60 minutes - full stack with 5 Helm charts + CRDs
            cleanupTimeoutSeconds = 1800  # 30 minutes
            skipDelete = False

            # ==============================================================
            # extraResources: RBAC, Helm ProviderConfig, Kubernetes ProviderConfig
            # These are NOT deleted during cleanup
            # ==============================================================
            extraResources = [
                # Grant cluster-admin to all SAs in crossplane-system namespace
                # Required for Helm provider to create namespaces and install charts,
                # and for Kubernetes provider to create Object resources
                {
                    apiVersion = "rbac.authorization.k8s.io/v1"
                    kind = "ClusterRoleBinding"
                    metadata.name = "crossplane-system-cluster-admin"
                    roleRef = {
                        apiGroup = "rbac.authorization.k8s.io"
                        kind = "ClusterRole"
                        name = "cluster-admin"
                    }
                    subjects = [
                        {
                            kind = "Group"
                            name = "system:serviceaccounts:crossplane-system"
                            apiGroup = "rbac.authorization.k8s.io"
                        }
                    ]
                }
                # Helm ProviderConfig - uses in-cluster identity
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = "default"
                        namespace = "default"
                    }
                    spec = {
                        credentials = {
                            source = "InjectedIdentity"
                        }
                    }
                }
                # Kubernetes ProviderConfig - uses in-cluster identity
                # Used by Object resources (Grafana CR + GrafanaDatasources)
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = "default"
                        namespace = "default"
                    }
                    spec = {
                        credentials = {
                            source = "InjectedIdentity"
                        }
                    }
                }
            ]

            # ==============================================================
            # manifests: Observe XR
            # Deleted during cleanup (unless --skip-delete)
            # ==============================================================
            manifests = [
                stacksv1alpha1.Observe {
                    metadata = {
                        name = _test_name
                        namespace = "default"
                    }
                    spec = {
                        clusterName = "default"
                        namespace = "monitoring"
                        labels = {
                            "hops.ops.com.ai/e2etest" = "true"
                            "hops.ops.com.ai/test-run" = _now
                        }
                        providerConfigRef = {
                            name = "default"
                            kind = "ProviderConfig"
                        }
                        kubernetesProviderConfigRef = {
                            name = "default"
                            kind = "ProviderConfig"
                        }
                        # Minimal resource requests for kind cluster
                        kubePrometheusStack.values = {
                            grafana = {
                                adminPassword = "e2e-test"
                                resources.requests = {cpu = "10m", memory = "64Mi"}
                            }
                            prometheus.prometheusSpec.resources.requests = {cpu = "10m", memory = "64Mi"}
                            alertmanager.alertmanagerSpec.resources.requests = {cpu = "10m", memory = "32Mi"}
                        }
                        loki.values = {
                            deploymentMode = "SingleBinary"
                            singleBinary.replicas = 1
                            loki.commonConfig.replication_factor = 1
                            loki.storage.type = "filesystem"
                            loki.schemaConfig.configs = [
                                {
                                    from = "2024-01-01"
                                    store = "tsdb"
                                    object_store = "filesystem"
                                    schema = "v13"
                                    index = {prefix = "index_", period = "24h"}
                                }
                            ]
                            backend.replicas = 0
                            read.replicas = 0
                            write.replicas = 0
                            chunksCache.enabled = False
                            resultsCache.enabled = False
                        }
                        tempo.values = {
                            tempo.resources.requests = {cpu = "10m", memory = "64Mi"}
                        }
                        k8sMonitoring.values = {
                            nodeExporter.enabled = False
                        }
                        grafanaOperator.values = {
                            resources.requests = {cpu = "10m", memory = "64Mi"}
                        }
                    }
                }
            ]
        }
    }
]
items = _items
