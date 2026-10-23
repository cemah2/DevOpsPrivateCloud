# plateforme/politiques — rego/tofu/commun.rego (M29-E03, PLAT-3003)
#
# Règles sur les plans OpenTofu de plateforme/infra, en Rego v1 (OPA 1.21, conftest 0.71).
# Entrée : la sortie de « tofu show -json plan.tfplan » (format JSON des plans, champ
# resource_changes[] : address, type, mode, change.actions, change.before, change.after).
# Données :
#   data.plages_vmid   rego/donnees/plages-vmid.yaml (plages de PLAN §4.6 par état)
#   data.contexte      contexte.json écrit par le job : {"contexte": {"etat": "<dossier>",
#                      "etiquettes_mr": ["…"]}} — etat = dossier de la configuration (socle,
#                      envs/m29…), etiquettes_mr = $CI_MERGE_REQUEST_LABELS découpé.
# Lancement (depuis la racine de plateforme/politiques) :
#   conftest test --namespace tofu -p rego/tofu --data rego/donnees --data contexte.json plan.json
# Tous les fichiers de rego/tofu/ sont dans le MÊME paquet « tofu » : conftest ne lit que
# l'espace qu'on lui donne (--namespace tofu) ; un fichier dans un autre paquet serait ignoré
# sans un mot (piège de M29-E11).
package tofu

# Le type de ressource des VMs du fournisseur bpg/proxmox (module vm-debian, vm-noeud).
type_vm := "proxmox_virtual_environment_vm"

# VMs que le plan crée ou modifie (création, mise à jour, remplacement). « read » (sources de
# données) et « no-op » ne comptent pas.
vms_creees_ou_modifiees contains rc if {
	some rc in input.resource_changes
	rc.type == type_vm
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

# VMs que le plan détruit, seules ou dans un remplacement (["delete","create"] ou
# ["create","delete"] avec create_before_destroy) : un remplacement EST une destruction.
vms_detruites contains rc if {
	some rc in input.resource_changes
	rc.type == type_vm
	rc.mode == "managed"
	"delete" in rc.change.actions
}

# Libellé lisible d'une liste d'actions, pour les messages.
action_lisible(actions) := "remplace" if {
	count(actions) == 2
} else := "détruit" if {
	actions == ["delete"]
} else := concat("+", actions)

# Étiquettes d'une VM après le plan (liste vide si absentes).
etiquettes_apres(rc) := object.get(rc.change.after, "tags", []) if {
	rc.change.after != null
} else := []

# Étiquettes d'une VM avant le plan (état connu), pour juger une destruction.
etiquettes_avant(rc) := object.get(rc.change.before, "tags", []) if {
	rc.change.before != null
} else := []

# Le contexte est obligatoire : sans lui, les règles qui dépendent de l'état ne diraient rien
# (une règle dont une donnée manque ne se déclenche pas : elle ÉCHOUE EN SILENCE).
deny contains msg if {
	not data.contexte.etat
	msg := "contexte absent : le job doit passer --data contexte.json avec contexte.etat (socle, envs/m29…)"
}
