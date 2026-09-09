#!/usr/bin/env bash
#
# Arrête l'application GSB lancée sans Docker.
# Les données sont conservées dans legacy/local/mysql/data.

set -uo pipefail
cd "$(dirname "$0")/.."          # -> legacy/

PORT_WEB=8089
LOCAL="$PWD/local"

echo
echo "  Arrêt de l'application GSB (mode sans Docker)"
echo

# --- serveur web ----------------------------------------------------------

if pkill -f "php -S 127.0.0.1:$PORT_WEB" 2>/dev/null; then
    echo "  serveur web arrêté"
else
    echo "  serveur web déjà arrêté"
fi

# --- base de données ------------------------------------------------------

PID_FILE="$LOCAL/mysql/mysql.pid"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    MB="$(brew --prefix mariadb 2>/dev/null)/bin"
    if [ -x "$MB/mariadb-admin" ]; then
        "$MB/mariadb-admin" --socket="$LOCAL/mysql/mysql.sock" -uroot -proot shutdown 2>/dev/null \
            && echo "  base de données arrêtée"
    else
        kill "$(cat "$PID_FILE")" 2>/dev/null && echo "  base de données arrêtée"
    fi
else
    echo "  base de données déjà arrêtée"
fi

echo
echo "  Les données saisies sont conservées."
echo "  Pour repartir d'une base vierge, supprimez le dossier legacy/local/mysql/data"
echo "  puis relancez ./sans-docker/demarrer-mac.sh"
echo
