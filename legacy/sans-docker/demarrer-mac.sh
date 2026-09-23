#!/usr/bin/env bash
#
# Démarre l'application GSB de 2013 SANS DOCKER, sous macOS.
#
# Installe ce qui manque avec Homebrew, monte une instance MariaDB dédiée dans
# legacy/local/, puis lance le serveur web intégré de PHP.
#
# Rien n'est installé en dehors de Homebrew et du dossier legacy/local/ :
# une éventuelle installation PHP ou MariaDB déjà présente n'est pas touchée.
#
# Le script est idempotent : on peut le relancer sans risque.

set -euo pipefail
cd "$(dirname "$0")/.."          # -> legacy/

PORT_WEB=8089
PORT_BASE=3307
LOCAL="$PWD/local"
SOCKET="$LOCAL/mysql/mysql.sock"

titre()  { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
info()   { printf '    \033[90m%s\033[0m\n' "$1"; }
souci()  { printf '    \033[33m%s\033[0m\n' "$1"; }
echouer() { printf '    \033[31m%s\033[0m\n' "$1"; exit 1; }

mkdir -p "$LOCAL/mysql/data" "$LOCAL/log"

# --------------------------------------------------------------------------- 1

titre "1/6  Outils"

command -v brew > /dev/null 2>&1 || echouer \
    "Homebrew est nécessaire. Installez-le depuis https://brew.sh puis relancez."

if ! brew list shivammathur/php/php@7.4 > /dev/null 2>&1; then
    info "installation de PHP 7.4, comptez quelques minutes"
    # PHP 7.4 n'est plus dans Homebrew officiel : ce dépôt communautaire en
    # fournit des versions compilées, y compris pour les Mac ARM.
    brew tap shivammathur/php > /dev/null 2>&1 || true
    brew install shivammathur/php/php@7.4
fi
PHP="$(brew --prefix shivammathur/php/php@7.4)/bin/php"
[ -x "$PHP" ] || echouer "PHP 7.4 introuvable après installation."
info "PHP $("$PHP" -r 'echo PHP_VERSION;')"

if ! brew list mariadb > /dev/null 2>&1; then
    info "installation de MariaDB"
    brew install mariadb
fi
MB="$(brew --prefix mariadb)/bin"
[ -x "$MB/mariadbd" ] || echouer "MariaDB introuvable après installation."
info "MariaDB $("$MB/mariadbd" --version | sed 's/.*Ver \([0-9.]*\).*/\1/')"

# --------------------------------------------------------------------------- 2

titre "2/6  Instance de base de données dédiée"

if [ ! -f "$LOCAL/mysql/my.cnf" ]; then
    cat > "$LOCAL/mysql/my.cnf" <<CONF
# Instance MariaDB dédiée à l'application GSB de 2013, isolée du poste.
[mysqld]
port                    = $PORT_BASE
bind-address            = 127.0.0.1
# Le code de 2013 insère une chaîne vide dans une colonne entière
# auto-incrémentée : MySQL le tolérait, le mode strict le refuse.
sql_mode                =
# Le code écrit tantôt « etat », tantôt « Etat » : sous Windows la casse était
# ignorée. À poser AVANT l'initialisation des données.
lower_case_table_names  = 1
skip-name-resolve
CONF
    info "configuration écrite"
fi

if [ ! -d "$LOCAL/mysql/data/mysql" ]; then
    info "initialisation des données, une seule fois"
    "$MB/mariadb-install-db" \
        --defaults-file="$LOCAL/mysql/my.cnf" \
        --datadir="$LOCAL/mysql/data" \
        --auth-root-authentication-method=normal > "$LOCAL/log/init-db.log" 2>&1 \
        || echouer "L'initialisation a échoué. Voir local/log/init-db.log"
fi

# --------------------------------------------------------------------------- 3

titre "3/6  Démarrage de la base"

demarree() { "$MB/mariadb" --socket="$SOCKET" -uroot -proot -e "SELECT 1" > /dev/null 2>&1; }

lancer_serveur() {
    "$MB/mariadbd" \
        --defaults-file="$LOCAL/mysql/my.cnf" \
        --datadir="$LOCAL/mysql/data" \
        --socket="$SOCKET" \
        --pid-file="$LOCAL/mysql/mysql.pid" \
        > "$LOCAL/log/mariadb.log" 2>&1 &

    for _ in $(seq 1 30); do
        sleep 1
        # Au tout premier démarrage, root n'a pas encore de mot de passe.
        if "$MB/mariadb" --socket="$SOCKET" -uroot -e "SELECT 1" > /dev/null 2>&1; then
            "$MB/mariadb" --socket="$SOCKET" -uroot -e "
                ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';
                ALTER USER 'root'@'127.0.0.1' IDENTIFIED BY 'root';
                FLUSH PRIVILEGES;" > /dev/null 2>&1 || true
            return 0
        fi
        demarree && return 0
        # Inutile d'attendre si le serveur a déjà abandonné.
        grep -q '\[ERROR\] Aborting' "$LOCAL/log/mariadb.log" 2>/dev/null && return 1
    done
    return 1
}

# Un arrêt brutal (extinction du Mac, fenêtre fermée) laisse des journaux
# incohérents, et le serveur refuse ensuite de démarrer. MariaDB indique
# lui-même la marche à suivre : écarter ces journaux, qu'il recrée. On les
# déplace dans un dossier daté plutôt que de les supprimer ; les données des
# tables ne sont pas touchées.
reparer_journaux() {
    local rebut="$LOCAL/mysql/ecartes/$(date +%Y%m%d-%H%M%S)"
    local fait=1
    if grep -q 'tc log' "$LOCAL/log/mariadb.log" 2>/dev/null && [ -f "$LOCAL/mysql/data/tc.log" ]; then
        mkdir -p "$rebut" && mv "$LOCAL/mysql/data/tc.log" "$rebut/" && fait=0
        souci "journal de transactions tc.log abîmé, écarté vers local/mysql/ecartes/"
    fi
    if grep -q 'Aria recovery failed' "$LOCAL/log/mariadb.log" 2>/dev/null; then
        mkdir -p "$rebut" && mv "$LOCAL"/mysql/data/aria_log* "$rebut/" 2>/dev/null && fait=0
        souci "journaux du moteur Aria abîmés, écartés vers local/mysql/ecartes/"
    fi
    return $fait
}

if demarree; then
    info "déjà en marche sur le port $PORT_BASE"
else
    if ! lancer_serveur; then
        if reparer_journaux; then
            info "nouvelle tentative de démarrage"
            lancer_serveur || true
        fi
    fi
    if ! demarree; then
        echo
        tail -8 "$LOCAL/log/mariadb.log" | sed 's/^/      /'
        echouer "La base n'a pas démarré. Journal complet : local/log/mariadb.log"
    fi
    info "démarrée sur le port $PORT_BASE"
fi

# --------------------------------------------------------------------------- 4

titre "4/6  Schéma et jeu d'essai"

existe=$("$MB/mariadb" --socket="$SOCKET" -uroot -proot -sN \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='bd_gsb';" 2>/dev/null || echo 0)

if [ "$existe" -lt 6 ]; then
    "$MB/mariadb" --socket="$SOCKET" -uroot -proot \
        -e "CREATE DATABASE IF NOT EXISTS bd_gsb CHARACTER SET utf8;"
    for f in sql/01-schema.sql sql/02-donnees.sql; do
        "$MB/mariadb" --socket="$SOCKET" -uroot -proot bd_gsb < "$f" \
            || echouer "Le chargement de $f a échoué."
        info "$f chargé"
    done
else
    info "base déjà peuplée, $existe tables"
fi

# --------------------------------------------------------------------------- 5

titre "5/6  Application Symfony"

# Composer sert aussi hors installation, pour regenerer l'autoloader.
if [ ! -f "$LOCAL/composer.phar" ]; then
    info "téléchargement de Composer"
    curl -fsSL https://getcomposer.org/composer-stable.phar -o "$LOCAL/composer.phar" \
        || echouer "Téléchargement de Composer impossible. Vérifiez le réseau ou le proxy."
fi

# Un vendor installe avant une mise a jour du composer.lock garde les anciennes
# versions (Twig 1.35 collait le texte avant chaque {{ }} sous PHP 7.4). Une
# copie du composer.lock, deposee dans vendor apres chaque installation, permet
# de le reperer.
TEMOIN_VERROU=app/vendor/.composer.lock.installe
if [ ! -d app/vendor ] || ! cmp -s app/composer.lock "$TEMOIN_VERROU"; then
    info "installation ou mise à jour des dépendances, comptez quelques minutes"
    if [ ! -f app/composer.json ]; then
        (cd app && "$PHP" "$LOCAL/composer.phar" create-project \
            symfony/framework-standard-edition /tmp/gsb-sf "2.8.*" \
            --no-interaction --prefer-dist --no-scripts)
        cp -an /tmp/gsb-sf/. app/
        rm -rf /tmp/gsb-sf
    fi
    (cd app && "$PHP" "$LOCAL/composer.phar" install --no-interaction --no-scripts)
    cp app/composer.lock "$TEMOIN_VERROU"
else
    info "dépendances déjà installées"
fi

# La connexion pointe vers l'instance locale, pas vers le service Docker.
cat > app/app/config/parameters.yml <<PARAM
# Généré par sans-docker/demarrer-mac.sh : instance MariaDB locale.
parameters:
    database_host:     127.0.0.1
    database_port:     $PORT_BASE
    database_name:     bd_gsb
    database_user:     root
    database_password: root
    mailer_transport:  smtp
    mailer_host:       127.0.0.1
    mailer_user:       ~
    mailer_password:   ~
    secret:            GsbDeuxMilleTreizeSansDocker
PARAM

python3 - "$PORT_BASE" <<'PY'
import pathlib, re, sys
port = sys.argv[1]
p = pathlib.Path('app/src/Pg/GsbFraisBundle/Resources/config/services.yml')
t = p.read_text()
t = re.sub(r'db\.host: mysql:host=[^\n]*',
           'db.host: mysql:host=127.0.0.1;port=%s' % port, t)
p.write_text(t)
PY
info "connexion dirigée vers 127.0.0.1:$PORT_BASE"

# Symfony 2.8 et Doctrine declenchent sur PHP 7.4 un avertissement
# « continue targeting switch » dans leur propre code. Il est sans consequence
# mais tres bavard : on le filtre, en laissant passer tout le reste.
(cd app \
    && "$PHP" "$LOCAL/composer.phar" dump-autoload --quiet \
    && "$PHP" vendor/sensio/distribution-bundle/Sensio/Bundle/DistributionBundle/Resources/bin/build_bootstrap.php app \
    && "$PHP" app/console assets:install web --symlink --env=prod --no-debug --quiet \
    && rm -rf app/cache/*) 2>&1 | grep -v 'continue.*targeting switch' | grep -v '^$' || true

[ -e app/web/bundles/gsbfrais ] \
    || ln -s ../../src/Pg/GsbFraisBundle/Resources/public app/web/bundles/gsbfrais
info "ressources publiées"

# --------------------------------------------------------------------------- 6

titre "6/6  Serveur web"

deja_lance=0
if lsof -nP -iTCP:$PORT_WEB -sTCP:LISTEN > /dev/null 2>&1; then
    pid=$(lsof -nP -iTCP:$PORT_WEB -sTCP:LISTEN -t 2>/dev/null | head -1)
    commande=$(ps -o command= -p "$pid" 2>/dev/null || true)
    # Notre propre serveur, lancé par une exécution précédente : on le garde.
    if [[ "$commande" == *"sans-docker/routeur.php"* ]]; then
        info "serveur web déjà en marche (processus $pid), il est conservé"
        deja_lance=1
    else
        nom=$(ps -o comm= -p "$pid" 2>/dev/null | xargs basename 2>/dev/null || echo "inconnu")
        souci "Le port $PORT_WEB est occupé par « $nom » (processus $pid), étranger au projet."
        souci "Arrêtez ce programme, ou changez PORT_WEB en tête de ce script."
        exit 1
    fi
fi

if [ "$deja_lance" -eq 0 ]; then
    ("$PHP" -d upload_max_filesize=6M -d post_max_size=32M -S 127.0.0.1:$PORT_WEB -t app/web sans-docker/routeur.php \
        > "$LOCAL/log/php-server.log" 2>&1 &)
fi

code=0
for _ in $(seq 1 15); do
    sleep 1
    code=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:$PORT_WEB/accueil" || echo 000)
    [ "$code" = "200" ] && break
done

echo
if [ "$code" = "200" ]; then
    printf '    \033[32mL'"'"'application répond : http://127.0.0.1:%s\033[0m\n' "$PORT_WEB"
    echo
    echo "    Comptes de démonstration"
    echo "      dandre  / oppg5    David André, quatre fiches, tous les états"
    echo "      cbedos  / gvide    Christian Bedos, trois fiches"
    echo "      pbentot / doypa    Pascal Bentot, une seule fiche"
    echo "      admin   / gsbadmin Administrateur : validation des fiches, comptes"
    echo
    echo "    Pour arrêter :  ./sans-docker/arreter-mac.sh"
    echo
else
    echouer "La page d'accueil ne répond pas, code $code. Voir local/log/php-server.log"
fi
