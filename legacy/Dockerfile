# Environnement de resurrection de l'application GSB de 2013.
# Symfony 2.8 est le dernier Symfony 2 ; il tourne sur PHP 7.4, derniere version
# de PHP disponible en image officielle pour l'architecture ARM des Mac recents.
FROM php:7.4-apache

# Les depots Debian sont bascules en HTTPS : sur le reseau utilise pour ce
# projet, le port 80 sortant est intercepte et apt recoit une erreur 400.
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g; s|http://security.debian.org|https://security.debian.org|g' /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends git unzip libicu-dev libzip-dev \
    && docker-php-ext-install pdo_mysql intl zip opcache \
    && rm -rf /var/lib/apt/lists/*

# Symfony 2 expose son point d'entree dans web/
ENV APACHE_DOCUMENT_ROOT=/var/www/html/web
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf \
    && a2enmod rewrite

# Sans ces deux directives, Apache ignore le .htaccess livre par Symfony : la
# racine du site liste le repertoire au lieu de servir le controleur frontal, et
# les liens symboliques d'assets ne sont pas suivis.
RUN printf '%s\n' \
      '<Directory /var/www/html/web>' \
      '    AllowOverride All' \
      '    Options FollowSymLinks' \
      '    Require all granted' \
      '</Directory>' \
      > /etc/apache2/conf-available/gsb.conf \
    && a2enconf gsb

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Le code de 2013 formate les dates sans fuseau explicite
RUN echo "date.timezone=Europe/Paris" > /usr/local/etc/php/conf.d/timezone.ini

WORKDIR /var/www/html
