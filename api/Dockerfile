# Atsede Teguhan PHP API -- Docker image (OPTIONAL deploy path)
# The PREFERRED path is 42web / InfinityFree PHP hosting (see docs/DEPLOY.md).
# This Dockerfile is only the alternative for running the same api/ code as
# a Render Docker web service. It contains NO secrets and copies NO .env
# file: all credentials come from environment variables at runtime
# (see api/config.php -- DB_HOST, DB_USER, DB_PASS, DB_NAME, JWT_SECRET).
FROM php:8.2-apache

# MySQL driver for PDO (used by api/config.php / api/db.php)
RUN docker-php-ext-install pdo pdo_mysql \
    && a2enmod rewrite

# Copy the PHP API into the Apache document root. The build context is
# the repo root, so this copies ./api/ (no .env file is committed).
COPY api/ /var/www/html/

EXPOSE 80
