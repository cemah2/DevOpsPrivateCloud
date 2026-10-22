# Norme « charge sûre » de MédiSphère

> `plateforme/medisphere` — `docs/securite/durcissement/charges-sures.md` (M26-E21, SEC-2721).
> S'applique à tout pod des espaces `mediagenda-*`, `medidoc-*` et des futurs espaces d'équipe.
> Mesure : `plateforme/k8s/outils/audit-charges-sures.sh` ; check `lab/bin/check 26 21`.
> Remplace et précise les règles `CNT-RUN-*` des normes de conteneurs (M12-E33).

| Critère | Exigence | Pourquoi | Où c'est imposé |
|---|---|---|---|
| C1 | `runAsNonRoot: true` et UID/GID numériques explicites | root dans le conteneur = root sur les fichiers montés, et un pas de moins vers l'hôte | Pod Security `restricted`, chart (`medisphere-commun.securite.pod`) |
| C2 | `allowPrivilegeEscalation: false` | bloque setuid et `no_new_privs` | Pod Security `restricted` |
| C3 | `readOnlyRootFilesystem: true` ; écritures dans des `emptyDir` **bornés** (`sizeLimit`) | rien ne se dépose dans l'image ; un disque plein n'évince pas tout le nœud | chart, Falco (« écriture sous /etc ») |
| C4 | `capabilities.drop: [ALL]`, aucun ajout | aucune capacité noyau inutile (`NET_RAW`, `SYS_PTRACE`…) | Pod Security `restricted` |
| C5 | seccomp `RuntimeDefault` (pod) ; AppArmor `RuntimeDefault` écrit | réduit la surface d'appels système ; ce qui est écrit se vérifie | Pod Security, Kyverno `seccomp-par-defaut` |
| C6 | aucun jeton de compte de service monté, sauf besoin écrit | un jeton volé est une identité dans le cluster | chart (`serviceAccount.automountToken: false`), Falco, registre EXC-K-002 |
| C7 | images par condensé hors `dev` (Harbor, signées) | ce qui tourne est ce qui a été analysé et signé | Kyverno `exiger-digest` (prod), `exiger-signature-medisphere` |
| C8 | `requests` CPU et mémoire, `limits` mémoire | ordonnancement prévisible, pas de voisin affamé ; pas de limite CPU (bridage, M21-E23) | Kyverno `exiger-limites`, LimitRange de l'espace |

## Ce qui n'est pas dans la norme (et pourquoi)

- **Limite de CPU** : elle bride sans protéger le nœud (les demandes suffisent à l'ordonnanceur) ; décision M21.
- **`noexec` sur `/tmp`** : un `emptyDir` ne se monte pas `noexec` ; la détection (Falco, Tetragon) prend le relais.
- **Profils seccomp ou AppArmor sur mesure** (`Localhost`) : coût d'entretien élevé, réservé aux charges
  exposées à Internet après mesure (fiche pour plus tard).

## Exceptions

Au registre [`exceptions.md`](exceptions.md) (procédure RB-261). Aujourd'hui : EXC-K-002 (jeton des
instances CloudNativePG).
