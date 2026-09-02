# Outils de production documentaire

Ces scripts servent à produire la version Word du cahier des charges à partir du Markdown. Le
Markdown reste la **source de vérité** : on ne modifie jamais le `.docx` à la main, on modifie le
`.md` puis on régénère.

## Ce que contient le dossier

- `md2docx.py` : conversion du Markdown vers Word. Écrit spécifiquement pour ce document, car les
  convertisseurs génériques rendent mal trois choses qu'il contient : les tableaux imbriqués dans des
  citations, les balises `<br>` à l'intérieur des cellules, et les blocs Mermaid.
- `mermaid-config.json` : thème des diagrammes de flux.
- `mermaid-config-etats.json` : thème du diagramme d'états, avec un espacement resserré, sans quoi le
  cycle de vie ne tient pas sur une page.

## Prérequis

| Outil | Installation |
| --- | --- |
| python-docx | `pip install python-docx` |
| Pillow | `pip install pillow` |
| mermaid-cli | `npm install -g @mermaid-js/mermaid-cli` |

## Régénérer le document

Depuis la racine du dépôt. Les diagrammes se rendent d'abord, la conversion les insère ensuite.

```bash
# 1. extraire les blocs Mermaid du Markdown vers un dossier de travail
mkdir -p /tmp/gsb-mmd
python3 - <<'EOF'
import re, pathlib
t = pathlib.Path('docs/cahier-des-charges.md').read_text()
for i, b in enumerate(re.findall(r'```mermaid\n(.*?)\n```', t, re.S)):
    pathlib.Path(f'/tmp/gsb-mmd/diag{i}.mmd').write_text(b + '\n')
EOF

# 2. rendre les diagrammes en PNG, le diagramme d'états avec son thème resserré
mmdc -i /tmp/gsb-mmd/diag0.mmd -o /tmp/gsb-mmd/diag0.png -c docs/outils/mermaid-config.json -b white -s 3
mmdc -i /tmp/gsb-mmd/diag1.mmd -o /tmp/gsb-mmd/diag1.png -c docs/outils/mermaid-config-etats.json -b white -s 3
mmdc -i /tmp/gsb-mmd/diag2.mmd -o /tmp/gsb-mmd/diag2.png -c docs/outils/mermaid-config.json -b white -s 3

# 3. produire le document Word
python3 docs/outils/md2docx.py docs/cahier-des-charges.md docs/cahier-des-charges.docx /tmp/gsb-mmd
```

Les images sont insérées dans l'ordre alphabétique des fichiers du dossier, qui doit donc correspondre
à l'ordre d'apparition des blocs Mermaid dans le document.

## Vérifier le rendu

LibreOffice convertit le résultat en PDF, ce qui permet de contrôler la pagination sans ouvrir Word.

```bash
soffice --headless --convert-to pdf --outdir /tmp docs/cahier-des-charges.docx
```

## Limites connues

- Le script traite le sous-ensemble de Markdown effectivement utilisé par le cahier des charges. Une
  syntaxe nouvelle, par exemple une liste de définitions ou une note de bas de page, ne serait pas
  rendue.
- Les largeurs de colonnes sont calculées à partir de la longueur du contenu. Un tableau très
  particulier peut demander un ajustement manuel des constantes en tête de script.
- Un diagramme plus haut que large est réduit pour tenir dans la page. Au-delà d'un rapport de trois
  pour un, son texte devient petit : mieux vaut alors revoir le diagramme que la conversion.
