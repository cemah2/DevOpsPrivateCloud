# plateforme/politiques — rego/kubernetes/charges.rego (M29-E10, PLAT-3010)
#
# Règles sur les MANIFESTES RENDUS (kustomize build, helm template), évaluées en MR par le
# composant CI/CD « validation » (conftest 0.71, Rego v1). Chaque document YAML est une entrée.
#   conftest test --namespace kubernetes -p rego/kubernetes rendu/*.yaml
#
# Pourquoi des règles ici alors que Kyverno (M26) refuse déjà à l'admission ? Kyverno juge ce
# qui arrive au cluster, à la synchronisation d'Argo CD, APRÈS la fusion. Les mêmes exigences
# évaluées sur le rendu, dans la MR, donnent le refus au relecteur, avant la fusion, sans cluster.
# On n'y met que des règles simples et stables ; la vérité reste celle de l'admission.
package kubernetes

registre := "registry.par1.medisphere.internal/"

# Types qui portent un gabarit de pod, et où il se trouve.
gabarit_pod := input.spec.template.spec if {
	input.kind in {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "Rollout"}
} else := input.spec.jobTemplate.spec.template.spec if {
	input.kind == "CronJob"
} else := input.spec if {
	input.kind == "Pod"
}

conteneurs contains c if {
	some c in object.get(gabarit_pod, "containers", [])
}

conteneurs contains c if {
	some c in object.get(gabarit_pod, "initContainers", [])
}

nom_objet := sprintf("%s/%s", [input.kind, object.get(input.metadata, "name", "?")])

# Une Rollout en workloadRef (M20) n'a pas de gabarit : rien à vérifier ici.

deny contains msg if {
	some c in conteneurs
	not startswith(c.image, registre)
	msg := sprintf("%s, conteneur %s : image %q hors du registre de MédiSphère (caches Harbor)", [nom_objet, c.name, c.image])
}

# Étiquette absente ou « latest » : l'image peut changer sans changement de code.
deny contains msg if {
	some c in conteneurs
	not contains(c.image, "@sha256:")
	etiquette_flottante(c.image)
	msg := sprintf("%s, conteneur %s : image %q sans version (ni étiquette fixe ni condensé)", [nom_objet, c.name, c.image])
}

etiquette_flottante(image) if {
	# dernier segment du chemin, sans le port éventuel du registre
	segments := split(image, "/")
	dernier := segments[count(segments) - 1]
	not contains(dernier, ":")
}

etiquette_flottante(image) if endswith(image, ":latest")

deny contains msg if {
	some c in conteneurs
	not c.resources.limits.memory
	msg := sprintf("%s, conteneur %s : pas de limite de mémoire", [nom_objet, c.name])
}
