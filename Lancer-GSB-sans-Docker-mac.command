#!/usr/bin/env bash
#
# Lanceur macOS de l'application GSB de 2013, SANS DOCKER.
# Double-clic depuis le Finder.
#
# Utilise PHP 7.4 et MariaDB installés par Homebrew, et une base isolée dans
# legacy/local/. Aucun conteneur, aucun droit administrateur.

cd "$(dirname "$0")" || exit 1
PORT=8089

echo ""
echo "  ┌────────────────────────────────────────────────┐"
echo "  │   GSB — application de 2013, sans Docker       │"
echo "  └────────────────────────────────────────────────┘"

if ! ./legacy/sans-docker/demarrer-mac.sh; then
    echo ""
    echo "  ÉCHEC : les messages ci-dessus indiquent où."
    echo "  Appuyez sur une touche pour fermer."
    read -r -n 1 -s
    exit 1
fi

open "http://127.0.0.1:$PORT"

echo "  Vous pouvez fermer cette fenêtre : l'application continue de tourner."
echo "  Pour l'arrêter, double-cliquez sur Arreter-GSB-sans-Docker-mac.command"
echo ""
echo "  Appuyez sur une touche pour fermer cette fenêtre."
read -r -n 1 -s
