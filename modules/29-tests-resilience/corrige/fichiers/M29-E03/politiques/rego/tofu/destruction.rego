# plateforme/politiques — rego/tofu/destruction.rego (M29-E03, PLAT-3003)
# Détruire ou remplacer une VM du socle (étiquette « socle » AVANT le plan) exige une décision
# visible : l'étiquette de MR « destruction-autorisee », posée par un Maintainer après relecture
# du plan (RB du M05). Un remplacement silencieux (changement d'un champ qui force la
# recréation) est le cas typique : le plan dit « -/+ », personne ne lit.
# Les destructions hors socle ne sont pas refusées, mais signalées (warn) dans le journal.
package tofu

etiquette_destruction := "destruction-autorisee"

destruction_autorisee if {
	etiquette_destruction in object.get(data.contexte, "etiquettes_mr", [])
}

deny contains msg if {
	some rc in vms_detruites
	"socle" in etiquettes_avant(rc)
	not destruction_autorisee
	msg := sprintf("%s : le plan %s une VM du socle (%s) ; étiquette de MR « %s » requise", [rc.address, action_lisible(rc.change.actions), object.get(rc.change.before, "name", "?"), etiquette_destruction])
}

warn contains msg if {
	some rc in vms_detruites
	not "socle" in etiquettes_avant(rc)
	msg := sprintf("%s : le plan %s la VM %s (hors socle) : vérifie que c'est voulu", [rc.address, action_lisible(rc.change.actions), object.get(rc.change.before, "name", "?")])
}

warn contains msg if {
	some rc in vms_detruites
	"socle" in etiquettes_avant(rc)
	destruction_autorisee
	msg := sprintf("%s : destruction d'une VM du socle AUTORISÉE par l'étiquette de MR « %s »", [rc.address, etiquette_destruction])
}
