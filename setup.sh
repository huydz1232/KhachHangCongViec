set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

DB_NAME="${DB_NAME:-odoo_minimal}"
DB_USER="${POSTGRES_USER:-odoo}"
DB_PASSWORD="${POSTGRES_PASSWORD:-odoo}"
HTTP_PORT="${HTTP_PORT:-8069}"
PG_PORT="${PG_PORT:-5431}"
NO_DOWN="false"

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Options:
    --db-name NAME        Database name (default: odoo_minimal)
    --db-user USER        Postgres user (default: odoo)
    --db-password PASS    Postgres password (default: odoo)
    --http-port PORT      Odoo HTTP port on host (default: 8069)
    --pg-port PORT        Postgres port on host (default: 5431)
    --no-down             Do not run compose down before starting
    -h, --help            Show this help

Examples:
    ./setup.sh
    ./setup.sh --db-name odoo_prod --http-port 8070
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db-name) DB_NAME="$2"; shift 2 ;;
        --db-user) DB_USER="$2"; shift 2 ;;
        --db-password) DB_PASSWORD="$2"; shift 2 ;;
        --http-port) HTTP_PORT="$2"; shift 2 ;;
        --pg-port) PG_PORT="$2"; shift 2 ;;
        --no-down) NO_DOWN="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

echo "Starting Odoo setup..."
echo "========================"

echo -e "\n${BLUE}[1/7]${NC} Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Docker is not installed.${NC}"
    echo "Install Docker Desktop: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Docker daemon is not running.${NC}"
    echo "Please start Docker Desktop and run this script again."
    exit 1
fi
echo -e "${GREEN}OK${NC} Docker is running"

echo -e "\n${BLUE}[2/7]${NC} Checking Compose command..."
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
else
    echo -e "${RED}Docker Compose is not available.${NC}"
    exit 1
fi
echo -e "${GREEN}OK${NC} Using: ${COMPOSE_CMD[*]}"

echo -e "\n${BLUE}[3/7]${NC} Validating required files..."
required_files=("docker-compose.yml" "entrypoint.sh" "odoo.conf.template")
for f in "${required_files[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}Missing required file: $f${NC}"
        exit 1
    fi
done
echo -e "${GREEN}OK${NC} Files are ready"

echo -e "\n${BLUE}[4/7]${NC} Preparing .env and data folders..."
touch .env

set_env_var() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" .env; then
        awk -v key="$key" -v value="$value" 'BEGIN{FS=OFS="="} $1==key{$2=value; print; next} {print}' .env > .env.tmp && mv .env.tmp .env
    else
        echo "${key}=${value}" >> .env
    fi
}

set_env_var "POSTGRES_DB" "postgres"
set_env_var "POSTGRES_USER" "$DB_USER"
set_env_var "POSTGRES_PASSWORD" "$DB_PASSWORD"
set_env_var "DB_NAME" "$DB_NAME"

mkdir -p _pgdata_b _odoo_data
chmod 777 _pgdata_b _odoo_data
echo -e "${GREEN}OK${NC} .env and data folders prepared"

echo -e "\n${BLUE}[5/7]${NC} Applying docker-compose port values..."
if ! grep -q '"${HTTP_PORT:-8069}:7000"' docker-compose.yml; then
    if grep -q '"8069:7000"' docker-compose.yml; then
        sed -i.bak 's/"8069:7000"/"${HTTP_PORT:-8069}:7000"/' docker-compose.yml && rm -f docker-compose.yml.bak
    fi
fi
if ! grep -q '"${PG_PORT:-5431}:5432"' docker-compose.yml; then
    if grep -q '"5431:5432"' docker-compose.yml; then
        sed -i.bak 's/"5431:5432"/"${PG_PORT:-5431}:5432"/' docker-compose.yml && rm -f docker-compose.yml.bak
    fi
fi
set_env_var "HTTP_PORT" "$HTTP_PORT"
set_env_var "PG_PORT" "$PG_PORT"
echo -e "${GREEN}OK${NC} Ports configured (HTTP=${HTTP_PORT}, PG=${PG_PORT})"

echo -e "\n${BLUE}[6/7]${NC} Starting containers..."
if [[ "$NO_DOWN" != "true" ]]; then
    "${COMPOSE_CMD[@]}" down >/dev/null 2>&1 || true
fi
"${COMPOSE_CMD[@]}" up -d
echo -e "${GREEN}OK${NC} Containers started"

echo -e "\n${BLUE}[7/7]${NC} Waiting for Odoo to be ready..."
MAX_ATTEMPTS=90
ATTEMPT=0
READY="false"
while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
    if curl -s -o /dev/null -w '%{http_code}' "http://localhost:${HTTP_PORT}/web" | grep -Eq '200|303'; then
        READY="true"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 2
done

if [[ "$READY" == "true" ]]; then
    echo -e "\n${GREEN}========================"
    echo "SETUP COMPLETED"
    echo -e "========================${NC}"
    echo ""
    echo "URL:        http://localhost:${HTTP_PORT}"
    echo "Database:   ${DB_NAME}"
    echo "Email:      admin"
    echo "Password:   admin"
    echo ""
    echo "Useful commands:"
    echo "  ${COMPOSE_CMD[*]} logs -f odoo"
    echo "  ${COMPOSE_CMD[*]} restart"
    echo "  ${COMPOSE_CMD[*]} down"
    echo "  ${COMPOSE_CMD[*]} down -v"
else
    echo -e "\n${YELLOW}Odoo is not ready yet after waiting.${NC}"
    echo "Check logs with: ${COMPOSE_CMD[*]} logs -f odoo"
    exit 1
fi
