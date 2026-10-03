# shellcheck shell=bash
# check-E40.sh — M00-E40 « Panne : la résolution DNS ne fonctionne plus » : retour à l'état sain.
title "M00-E40 — Panne : la résolution DNS ne fonctionne plus"
require_cmd dig getent

check_ssh "dns01 : service dnsmasq actif" dns01 "systemctl is-active -q dnsmasq"
check_ssh "dns01 : configuration dnsmasq valide" dns01 "sudo -n dnsmasq --test"
check_cmd "adm01 → dns01 : DNS en UDP" dig +notcp +time=3 +tries=1 @10.10.20.10 dns01.par1.medisphere.internal A
check_cmd "adm01 → dns01 : DNS en TCP" dig +tcp +time=3 +tries=1 @10.10.20.10 dns01.par1.medisphere.internal A
check_dns "zone locale : adm01.par1.medisphere.internal" adm01.par1.medisphere.internal A '^10\.10\.10\.10$' 10.10.20.10
check_dns "zone locale : enregistrement inverse de 10.10.10.10" 10.10.10.10.in-addr.arpa PTR '^adm01\.par1\.medisphere\.internal\.$' 10.10.20.10
check_dns "zone PAR2 : pbs01.par2.medisphere.internal" pbs01.par2.medisphere.internal A '^10\.20\.10\.10$' 10.10.20.10
check_dns "récursion vers Internet : deb.debian.org" deb.debian.org A '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' 10.10.20.10
check_cmd "adm01 : résolveur système, nom court du lab (domaine de recherche)" getent hosts dns01
check_cmd "adm01 : résolveur système, nom externe" getent hosts deb.debian.org
check_ssh "dns01 : résolveur système, nom externe" dns01 "getent hosts deb.debian.org"
