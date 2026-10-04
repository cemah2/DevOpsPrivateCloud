# Politique de rétention des rapports applicatifs (PLAT-384, validée par Sophie Laurent)

Les applications déposent leurs rapports (JSON et PDF) sous une racine commune, un dossier par application :

```
<RACINE>/
├── medi-agenda/
│   ├── rapport-AAAA-MM-JJ.json, rapport-AAAA-MM-JJ.pdf, « Rapport mensuel AAAA-MM.pdf », LISEZMOI.txt
│   ├── a-conserver/        pièces sous conservation légale (contentieux, audits HDS)
│   └── tmp/                fichiers de travail (facultatif : toutes les applications n'en ont pas)
├── medi-doc/ …
├── medi-notif/ …
└── legacy-rdv/            application retirée
```

Règles, dans cet ordre :

1. **Applications retirées** : le dossier de chaque application listée dans `APPLIS_RETIREES` est supprimé entièrement (ses archives ont été versées au coffre d'archivage avant le retrait).
2. **Fichiers de travail** : le contenu du dossier `tmp/` de chaque application est vidé, quel que soit son âge. Le dossier `tmp/` lui-même reste.
3. **Rapports** : les fichiers `*.json` et `*.pdf` modifiés il y a plus de `RETENTION_JOURS` jours sont supprimés.

Exceptions, sans aucune dérogation :

- rien n'est jamais supprimé dans un dossier `a-conserver/` d'une application active (obligation légale) ;
- les autres types de fichiers (`LISEZMOI.txt`…) ne sont pas concernés ;
- rien n'est jamais touché hors de `<RACINE>`.

Configuration (fichier `purge.conf`, syntaxe shell) :

```
RACINE=/chemin/absolu/vers/rapports
RETENTION_JOURS=30
APPLIS_RETIREES="legacy-rdv"
```

Sécurité : la racine contient un fichier témoin `.zone-de-test` (en production : `.zone-purgeable`). Un outil de purge refuse de travailler sur une racine qui n'en contient pas.

Codes retour attendus (convention de `plateforme/outils`) : `0` succès, `1` erreur, `2` usage, `3` refus d'un garde-fou.
