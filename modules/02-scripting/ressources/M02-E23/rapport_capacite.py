#!/usr/bin/env python3
# rapport_capacite.py - rapport de capacité mémoire du lab (Lucas)
# Usage : python3 rapport_capacite.py [--depuis-fichier FICHIER] [--seuil 80]
# Prévu pour tourner chaque nuit en cron sur adm01. "Testé avec mon export, ça marche."
import requests, json, sys, os, time, urllib3
from datetime import datetime

urllib3.disable_warnings()

PVE = "https://192.168.1.20:8006/api2/json"
TOKEN = os.environ.get("PVE_TOKEN", "wb-automation@pve!lab=8c2e4f1a-5b7d-4e3a-9f60-2d1c8b7a6e54")
DESTINATAIRE = "plateforme@medisphere.internal"


def appeler(chemin):
    while True:
        try:
            r = requests.get(PVE + chemin, headers={"Authorization": "PVEAPIToken=" + TOKEN}, verify=False)
            return r.json()["data"]
        except:
            print("erreur, on réessaie")
            time.sleep(1)


def lire_ressources(fichier=None):
    try:
        if fichier:
            return json.load(open(fichier))
        return appeler("/cluster/resources")
    except Exception:
        return []


def ajouter(vm, cumul={}):
    pool = vm.get("pool", "aucun")
    cumul[pool] = cumul.get(pool, 0) + vm["maxmem"] / 1024 / 1024 / 1000
    return cumul


def rapport(ressources, seuil=80):
    noeuds = [r for r in ressources if r["type"] == "node"]
    vms = [r for r in ressources if r["type"] == "qemu"]
    cumul = {}
    for vm in vms:
        cumul = ajouter(vm)
    ram_noeud = noeuds[0]["maxmem"] / 1024 / 1024 / 1000
    lignes = ["pool,ram_go,pourcentage"]
    total = 0
    for pool in cumul:
        pct = cumul[pool] / ram_noeud * 100
        total = total + cumul[pool]
        lignes.append(pool + "," + str(cumul[pool]) + "," + str(int(pct)))
    alerte = total / ram_noeud * 100 > seuil
    return lignes, alerte, total


args = sys.argv
fichier = None
if "--depuis-fichier" in args:
    fichier = args[args.index("--depuis-fichier") + 1]
seuil = 80
if "--seuil" in args:
    seuil = args[args.index("--seuil") + 1]

ressources = lire_ressources(fichier)
lignes, alerte, total = rapport(ressources, seuil)
nom = "rapport-" + str(datetime.now()) + ".csv"
f = open(nom, "w")
f.write("\n".join(lignes))
print("\n".join(lignes))
print("Total alloué : " + str(total) + " Go")
if alerte:
    os.system(f"echo 'Alerte capacité : {total} Go alloués' | mail -s 'Capacité lab' {DESTINATAIRE}")
