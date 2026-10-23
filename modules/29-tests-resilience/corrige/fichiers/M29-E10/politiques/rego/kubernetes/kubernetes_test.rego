# plateforme/politiques — rego/kubernetes/kubernetes_test.rego (M29-E10, PLAT-3010)
#   opa test rego/kubernetes -v
package kubernetes_test

import data.kubernetes

deploiement(image, limites) := {
	"apiVersion": "apps/v1",
	"kind": "Deployment",
	"metadata": {"name": "api"},
	"spec": {"template": {"spec": {"containers": [{"name": "api", "image": image, "resources": {"limits": limites}}]}}},
}

image_ok := "registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

test_deploiement_conforme if {
	count(kubernetes.deny) == 0 with input as deploiement(image_ok, {"memory": "256Mi"})
}

test_image_etiquetee_conforme if {
	count(kubernetes.deny) == 0 with input as deploiement("registry.par1.medisphere.internal/dockerhub/valkey/valkey:9.1.2-trixie", {"memory": "256Mi"})
}

test_image_hors_registre_refusee if {
	some msg in kubernetes.deny with input as deploiement("docker.io/library/nginx:1.29", {"memory": "64Mi"})
	contains(msg, "hors du registre")
}

test_image_sans_etiquette_refusee if {
	some msg in kubernetes.deny with input as deploiement("registry.par1.medisphere.internal/medisphere/mediagenda-api", {"memory": "64Mi"})
	contains(msg, "sans version")
}

test_image_latest_refusee if {
	some msg in kubernetes.deny with input as deploiement("registry.par1.medisphere.internal/medisphere/mediagenda-api:latest", {"memory": "64Mi"})
	contains(msg, "sans version")
}

# Le port d'un registre n'est pas une étiquette.
test_port_du_registre_n_est_pas_une_etiquette if {
	some msg in kubernetes.deny with input as deploiement("registry.par1.medisphere.internal:443/medisphere/api", {"memory": "64Mi"})
	contains(msg, "sans version")
}

test_sans_limite_memoire_refuse if {
	some msg in kubernetes.deny with input as deploiement(image_ok, {"cpu": "1"})
	contains(msg, "pas de limite de mémoire")
}

test_cronjob_inspecte if {
	cj := {
		"apiVersion": "batch/v1", "kind": "CronJob", "metadata": {"name": "export"},
		"spec": {"jobTemplate": {"spec": {"template": {"spec": {"containers": [{"name": "c", "image": "alpine:3"}]}}}}},
	}
	count(kubernetes.deny) >= 2 with input as cj
}

test_objet_sans_pod_ignore if {
	count(kubernetes.deny) == 0 with input as {"apiVersion": "v1", "kind": "Service", "metadata": {"name": "s"}, "spec": {}}
}

espace(nom, annotations) := {"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": nom, "annotations": annotations}}

test_annotation_chaos_autorisee_en_recette if {
	count(kubernetes.deny) == 0 with input as espace("mediagenda-recette", {"chaos-mesh.org/inject": "enabled"})
}

test_annotation_chaos_refusee_en_prod if {
	some msg in kubernetes.deny with input as espace("mediagenda-prod", {"chaos-mesh.org/inject": "enabled"})
	contains(msg, "interdite")
}

test_experience_sans_duree_refusee if {
	some msg in kubernetes.deny with input as {
		"apiVersion": "chaos-mesh.org/v1alpha1", "kind": "NetworkChaos", "metadata": {"name": "latence"},
		"spec": {"action": "delay", "mode": "one", "selector": {"namespaces": ["mediagenda-recette"]}},
	}
	contains(msg, "sans spec.duration")
}

test_pod_kill_sans_duree_accepte if {
	count(kubernetes.deny) == 0 with input as {
		"apiVersion": "chaos-mesh.org/v1alpha1", "kind": "PodChaos", "metadata": {"name": "tuer"},
		"spec": {"action": "pod-kill", "mode": "one", "selector": {"namespaces": ["mediagenda-recette"]}},
	}
}
