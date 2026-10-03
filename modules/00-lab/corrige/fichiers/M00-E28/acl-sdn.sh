#!/usr/bin/env bash
# acl-sdn.sh — Droits d'usage des VNets de la zone « lab » (M00-E28).
set -euo pipefail

# Humains : rôle prédéfini PVESDNUser (SDN.Use + SDN.Audit), propagé à tous les VNets de la zone.
pveum acl modify /sdn/zones/lab --groups wb-admins --roles PVESDNUser

# Automatisation : avec la séparation des privilèges, le jeton n'a que l'intersection
# de SES droits et de ceux de l'utilisateur : il faut donc les deux ACL.
pveum acl modify /sdn/zones/lab --users wb-automation@pve --roles PVESDNUser
pveum acl modify /sdn/zones/lab --tokens 'wb-automation@pve!lab' --roles PVESDNUser

# Contrôle des droits effectifs
pveum user permissions wb-admin@pve --path /sdn/zones/lab/vinfra
pveum user token permissions wb-automation@pve lab --path /sdn/zones/lab/vsandbox
