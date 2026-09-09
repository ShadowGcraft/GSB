#!/usr/bin/env bash
# Arrête l'application GSB lancée sans Docker. Double-clic depuis le Finder.
cd "$(dirname "$0")" || exit 1
./legacy/sans-docker/arreter-mac.sh
echo "  Appuyez sur une touche pour fermer cette fenêtre."
read -r -n 1 -s
