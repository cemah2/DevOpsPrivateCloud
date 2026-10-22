# tofu/cles.tf — clés de signature du royaume medisphere (M24-E29, SEC-2529 ; RB-244).
#
# Keycloak signe avec la clé ACTIVE de plus haute PRIORITÉ ; une clé PASSIVE (active = false) ne signe
# plus mais reste PUBLIÉE dans le JWKS et vérifie les jetons qu'elle a signés ; une clé DÉSACTIVÉE
# (enabled = false) disparaît du JWKS : les jetons qu'elle a signés sont refusés partout.
#
# Rotation annuelle (RB-244) :
#   1. ajouter la clé de l'année, priorité supérieure, active → elle signe tout nouveau jeton ;
#   2. passer l'ancienne en passive (active = false), ATTENDRE la plus longue durée de vie d'un jeton
#      qu'elle a signé (session SSO maximale : 10 h ; on attend 24 h) ;
#   3. la désactiver (enabled = false) ; l'année suivante, supprimer le bloc (la clé est détruite).

# Fournisseur d'origine, créé avec le royaume en M24-E05 (« rsa-generated », priorité 100), importé
# ici pour pouvoir le passer en passive puis le désactiver par le code. Identifiant d'import :
# medisphere/<ID du composant> (console : Realm settings → Keys → Providers, ou API components).
import {
  to = keycloak_realm_keystore_rsa_generated.origine
  id = "medisphere/<ID-DU-FOURNISSEUR-rsa-generated>"
}

resource "keycloak_realm_keystore_rsa_generated" "origine" {
  realm_id  = keycloak_realm.medisphere.id
  name      = "rsa-generated"
  priority  = 100
  algorithm = "RS256"
  key_size  = 2048
  # Étape 2 : false (passive). Étape 3, 24 h plus tard au moins : enabled = false.
  active  = false
  enabled = false
}

resource "keycloak_realm_keystore_rsa_generated" "rsa_2026_10" {
  realm_id  = keycloak_realm.medisphere.id
  name      = "rsa-2026-10"
  priority  = 200
  algorithm = "RS256"
  key_size  = 4096 # le fournisseur n'accepte que 1024, 2048, 4096 (Keycloak accepterait 3072)
  active    = true
  enabled   = true
}
