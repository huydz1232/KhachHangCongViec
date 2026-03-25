#!/bin/bash
set -e

DB_NAME=${DB_NAME:-odoo_db}

# Wait for postgres to be ready
until pg_isready -h postgres-odoo-base -U odoo; do
  echo "Waiting for postgres..."
  sleep 2
done

# Create database if it doesn't exist
export PGPASSWORD=odoo
createdb -h postgres-odoo-base -U odoo "$DB_NAME" || echo "Database $DB_NAME already exists"

# Initialize database with only target business modules.
# Odoo will automatically install required dependencies.
odoo -d "$DB_NAME" --init base,quan_ly_khach_hang,quan_ly_cong_viec --without-demo=all --stop-after-init

# Start Odoo
exec odoo -d "$DB_NAME"