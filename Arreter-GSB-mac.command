#!/usr/bin/env bash
#
# Arrête l'application GSB de 2013. Double-clic depuis le Finder.
#
# Les données saisies sont conservées : au prochain démarrage, on les retrouve.
# Pour repartir d'une base vierge, lancez plutôt, dans le Terminal :
#     cd legacy && docker compose down -v

cd "$(dirname "$0")" || exit 1

echo ""
echo "  Arrêt de l'application GSB..."
echo ""

if ! docker info > /dev/null 2>&1; then
    echo "  Docker ne tourne pas : il n'y a rien à arrêter."
else
    (cd legacy && docker compose down)
    echo ""
    echo "  Application arrêtée. Les données sont conservées."
fi

echo ""
echo "  Docker lui-même continue de tourner. Pour l'arrêter aussi et libérer"
echo "  la mémoire, tapez dans le Terminal :  colima stop"
echo ""
echo "  Appuyez sur une touche pour fermer cette fenêtre."
read -r -n 1 -s
