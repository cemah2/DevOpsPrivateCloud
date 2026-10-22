#!/usr/bin/env bash
# pve01 — identité Proxmox de la supervision témoin (M21-E12, PLAT-2212), à lancer en root sur pve01.
# Idempotent : ce qui existe déjà est laissé tel quel. Le secret du jeton n'est affiché qu'à sa
# création : recopie-le aussitôt dans le Vault critique (vault_supervision_pve_jeton) et dans
# ~/.config/workbook/pve-supervision.env (600) sur adm01.
set -Eeuo pipefail

utilisateur='wb-supervision@pve'
jeton='prometheus'

if ! pveum user list --output-format json | grep -q "\"userid\":\"$utilisateur\""; then
  pveum user add "$utilisateur" --comment "Supervision témoin mon01 (M21-E12), lecture seule"
fi
if ! pveum user token list "$utilisateur" --output-format json | grep -q "\"tokenid\":\"$jeton\""; then
  # --privsep 1 : le jeton n'a AUCUN droit de l'utilisateur ; on lui en donne explicitement.
  pveum user token add "$utilisateur" "$jeton" --privsep 1 --comment "pve-exporter de mon01"
fi
# Rôle intégré PVEAuditor (lecture seule) sur /, pour le JETON.
pveum acl modify / --tokens "$utilisateur!$jeton" --roles PVEAuditor

echo "== Droits effectifs du jeton"
pveum user token permissions "$utilisateur" "$jeton"
