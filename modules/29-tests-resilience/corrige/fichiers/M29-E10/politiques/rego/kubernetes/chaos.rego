# plateforme/politiques — rego/kubernetes/chaos.rego (M29-E10, PLAT-3010)
# Le filtre d'espaces de Chaos Mesh (M29-E09) n'injecte que dans les espaces annotés
# chaos-mesh.org/inject=enabled. La liste est FERMÉE : mediagenda-recette, medinotif-recette,
# wb-essais. Le cluster le garantit (ValidatingAdmissionPolicy medisphere-chaos-espaces, M29-E09) ;
# cette règle le dit dans la MR de plateforme/k8s, avant même la fusion.
package kubernetes

espaces_chaos_autorises := {"mediagenda-recette", "medinotif-recette", "wb-essais"}

deny contains msg if {
	input.kind == "Namespace"
	object.get(object.get(input.metadata, "annotations", {}), "chaos-mesh.org/inject", "") == "enabled"
	not input.metadata.name in espaces_chaos_autorises
	msg := sprintf("Namespace/%s : annotation chaos-mesh.org/inject=enabled interdite hors de %v (M29-E09)", [input.metadata.name, espaces_chaos_autorises])
}

# Une expérience de chaos sans durée ne s'arrête que si quelqu'un la supprime (M29-E09, E20).
# Les types sans durée (PodChaos pod-kill / container-kill, actions ponctuelles) en sont exemptés.
types_avec_duree := {"NetworkChaos", "StressChaos", "IOChaos", "TimeChaos", "HTTPChaos", "DNSChaos"}

deny contains msg if {
	input.apiVersion == "chaos-mesh.org/v1alpha1"
	duree_exigee
	not input.spec.duration
	msg := sprintf("%s/%s : expérience de chaos sans spec.duration", [input.kind, input.metadata.name])
}

duree_exigee if input.kind in types_avec_duree

duree_exigee if {
	input.kind == "PodChaos"
	input.spec.action == "pod-failure"
}
