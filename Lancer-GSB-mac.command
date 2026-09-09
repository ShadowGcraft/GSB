#!/usr/bin/env bash
#
# Lanceur macOS de l'application GSB de 2013.
#
# Se lance d'un double-clic depuis le Finder. Si macOS refuse de l'ouvrir,
# c'est que le fichier a perdu son droit d'exécution : ouvrez le Terminal
# dans ce dossier et tapez  chmod +x Lancer-GSB-mac.command
#
# Le script démarre Docker si besoin, met l'application en route, puis ouvre
# le navigateur. Il n'y a rien d'autre à faire.

cd "$(dirname "$0")" || exit 1

PORT=8088
ADRESSE="http://localhost:$PORT"

echo ""
echo "  ┌────────────────────────────────────────────────┐"
echo "  │   GSB — application de 2013                    │"
echo "  └────────────────────────────────────────────────┘"
echo ""

echouer() {
    echo ""
    echo "  ÉCHEC : $1"
    echo ""
    echo "  Cette fenêtre reste ouverte pour que le message soit lisible."
    echo "  Appuyez sur une touche pour la fermer."
    read -r -n 1 -s
    exit 1
}

# --- Docker ---------------------------------------------------------------

if ! command -v colima > /dev/null 2>&1; then
    echouer "Colima n'est pas installé.
           Installez-le avec :  brew install colima docker docker-compose"
fi

if ! docker info > /dev/null 2>&1; then
    echo "  Démarrage de Docker, comptez une minute..."
    colima start || echouer "Colima n'a pas démarré."
    echo "  Docker est prêt."
else
    echo "  Docker tourne déjà."
fi

# --- application ----------------------------------------------------------

echo ""
if ! ./legacy/mise-en-route.sh; then
    echouer "La mise en route a échoué. Les messages ci-dessus indiquent où."
fi

# --- navigateur -----------------------------------------------------------

echo "  Ouverture du navigateur sur $ADRESSE"
open "$ADRESSE"

echo ""
echo "  ────────────────────────────────────────────────"
echo "  L'application tourne. Vous pouvez fermer cette fenêtre :"
echo "  elle continuera de fonctionner en arrière-plan."
echo ""
echo "  Pour l'arrêter plus tard, double-cliquez sur Arreter-GSB-mac.command"
echo "  ────────────────────────────────────────────────"
echo ""
echo "  Appuyez sur une touche pour fermer cette fenêtre."
read -r -n 1 -s
