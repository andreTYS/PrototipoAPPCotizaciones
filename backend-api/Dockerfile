FROM php:8.3-apache

# pdo_pgsql necesita libpq (cliente de Postgres) para compilar — no viene en
# la imagen base de php:apache, solo pdo_mysql/mysqli.
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev \
    && docker-php-ext-install pdo_pgsql \
    && apt-get purge -y --auto-remove libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Límite de subida para fotos de productos/maletas (ver uploads/ más abajo).
RUN { \
    echo 'upload_max_filesize = 20M'; \
    echo 'post_max_size = 20M'; \
    } > /usr/local/etc/php/conf.d/uploads.ini

WORKDIR /var/www/html
COPY . /var/www/html/

# Carpeta donde se suben/sirven las fotos reales (productos/, maletas/) —
# volumen aparte en docker-compose para que sobreviva a cada rebuild.
RUN mkdir -p /var/www/html/uploads && chown -R www-data:www-data /var/www/html/uploads

EXPOSE 80
