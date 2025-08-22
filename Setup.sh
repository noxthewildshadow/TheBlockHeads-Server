#!/usr/bin/env bash
# /usr/local/bin/blockheads
# Script de gestión para The Blockheads Server
# Uso: blockheads [create|start|list|delete|help] ...

set -euo pipefail

# ---------------------------
# Configuración (ajustable)
# ---------------------------

# Directorio del servidor (asegúrate de que coincide con la instalación)
SERVER_DIR="/opt/blockheads-server"
SERVER_BIN="${SERVER_DIR}/blockheads_server171"

# Determinar el directorio de mundos en tiempo de ejecución
determine_worlds_dir() {
    local user_home=""
    if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)"
    fi
    if [[ -z "$user_home" ]]; then
        # si no hay SUDO_USER (ejecutando como usuario normal), usar HOME
        user_home="${HOME:-}"
    fi
    # Fallback: si aún vacío, intentar /root
    if [[ -z "$user_home" ]]; then
        user_home="/root"
    fi

    WORLDS_DIR="${user_home}/GNUstep/Library/ApplicationSupport/TheBlockheads/Saves"
    # crear si no existe
    mkdir -p "$WORLDS_DIR"
}

# ---------------------------
# Colores (salida)
# ---------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() { echo -e "${GREEN}[+]${NC} $*"; }
print_error()  { echo -e "${RED}[-]${NC} $*"; }
print_warn()   { echo -e "${YELLOW}[!]${NC} $*"; }

# ---------------------------
# Comprobaciones iniciales
# ---------------------------
check_prereqs() {
    if [[ ! -x "$SERVER_BIN" ]]; then
        print_error "No se encontró o no es ejecutable el binario del servidor en: $SERVER_BIN"
        exit 1
    fi

    # comprobar que --list funciona (si falla, mostrar la salida de error)
    if ! "$SERVER_BIN" --list >/dev/null 2>&1; then
        print_warn "Advertencia: '$SERVER_BIN --list' devolvió error o salida vacía. Asegúrate de que el binario funciona correctamente."
        # no salimos: puede que el servidor esté bien y la opción requiera entornos. Dejamos continuar.
    fi
}

# ---------------------------
# Helpers para parseo de --list
# ---------------------------
# Quitar códigos ANSI
_strip_ansi() {
    # elimina secuencias ANSI comunes
    sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

# Itera cada línea de --list y devuelve pares ID|NOMBRE
# Formato esperado en cada línea: "<ID> <NOMBRE...>"
# Esta función no imprime nada; se usa en while-read con proceso sustituto.
# Ejemplo de uso:
# while IFS=$'\t' read -r id name; do ...; done < <(_list_worlds_parsed)
_list_worlds_parsed() {
    "$SERVER_BIN" --list 2>/dev/null | _strip_ansi | awk '
    # Ignorar líneas vacías o encabezados que no empiecen por id-like
    {
        if ($0 ~ /^[[:space:]]*$/) next;
        # capturar primer token como id y el resto como nombre
        id = $1;
        # reconstruir el nombre (campo 2 en adelante)
        name = "";
        for (i = 2; i <= NF; i++) {
            name = name (i==2 ? $i : " " $i);
        }
        # eliminar comillas al inicio/fin
        gsub(/^["\047]+|["\047]+$/, "", name);
        print id "\t" name;
    }'
}

# ---------------------------
# Buscar ID por nombre (exact match)
# ---------------------------
get_world_id_by_name() {
    local world_name="$1"
    # iterar las líneas parseadas
    while IFS=$'\t' read -r id name; do
        # comparar exactamente (case-sensitive). Si quieres case-insensitive usar tolower.
        if [[ "$name" == "$world_name" ]]; then
            printf '%s' "$id"
            return 0
        fi
    done < <(_list_worlds_parsed)
    return 1
}

# ---------------------------
# Verificar existencia por ID (primer token)
# ---------------------------
world_exists() {
    local world_id="$1"
    while IFS=$'\t' read -r id name; do
        if [[ "$id" == "$world_id" ]]; then
            return 0
        fi
    done < <(_list_worlds_parsed)
    return 1
}

# ---------------------------
# Comandos
# ---------------------------
show_help() {
    cat <<EOF
Uso: blockheads [COMANDO] [ARGUMENTOS]

Comandos:
  create <NOMBRE_MUNDO> [OPCIONES]  Crear un nuevo mundo
  start <ID_O_NOMBRE> [PUERTO]      Iniciar un mundo existente (acepta ID o nombre)
  list                              Listar todos los mundos
  delete <ID_O_NOMBRE>              Eliminar un mundo (acepta ID o nombre)
  help                              Mostrar esta ayuda

Opciones para create:
  -p, --port PORT                   Puerto del servidor (por defecto: 15151)
  -m, --max-players MAX             Máximo de jugadores (por defecto: 16; máximo: 32)
  -w, --world-width TAMAÑO          Tamaño del mundo (1/16, 1/4, 1, 4, 16)
  -e, --expert-mode                 Habilitar modo experto
  -o, --owner PROPIETARIO           Establecer propietario del mundo

Ejemplos:
  blockheads create "Mi Mundo Bonito" -p 15152 -m 12
  blockheads start 83cad395edb8d0f1912 15151
  blockheads start "Mi Mundo Bonito"
  blockheads delete 83cad395edb8d0f1912
EOF
}

create_world() {
    if [[ -z "${1:-}" ]]; then
        print_error "Se requiere un nombre para el mundo."
        exit 1
    fi
    local world_name="$1"; shift

    # construir array de args seguros
    local -a args=(--new "$world_name")
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)
                if [[ -z "${2:-}" ]]; then print_error "Falta valor para --port"; exit 1; fi
                args+=(--port "$2"); shift 2
                ;;
            -m|--max-players)
                if [[ -z "${2:-}" ]]; then print_error "Falta valor para --max-players"; exit 1; fi
                args+=(--max_players "$2"); shift 2
                ;;
            -w|--world-width)
                if [[ -z "${2:-}" ]]; then print_error "Falta valor para --world-width"; exit 1; fi
                args+=(--world_width "$2"); shift 2
                ;;
            -e|--expert-mode)
                args+=(--expert-mode); shift
                ;;
            -o|--owner)
                if [[ -z "${2:-}" ]]; then print_error "Falta valor para --owner"; exit 1; fi
                args+=(--owner "$2"); shift 2
                ;;
            *)
                print_error "Opción desconocida: $1"
                exit 1
                ;;
        esac
    done

    cd "$SERVER_DIR" || { print_error "No se puede acceder a $SERVER_DIR"; exit 1; }

    print_status "Creando mundo: $world_name"
    # Ejecutar la creación
    "$SERVER_BIN" "${args[@]}"

    # Intentar obtener el ID del mundo recién creado (reintentos cortos por si la lista tarda en actualizarse)
    local world_id=""
    for i in {1..6}; do
        sleep 1
        if world_id="$(get_world_id_by_name "$world_name")"; then
            break
        fi
    done

    if [[ -n "$world_id" ]]; then
        echo "Mundo creado con éxito. ID: $world_id"
        echo "Para iniciarlo: blockheads start $world_id"
    else
        print_warn "Mundo creado, pero no se pudo determinar el ID automáticamente."
        print_warn "Ejecuta 'blockheads list' para ver la lista de mundos."
    fi
}

start_world() {
    if [[ -z "${1:-}" ]]; then
        print_error "Se requiere el ID o nombre del mundo a iniciar."
        exit 1
    fi
    local world_identifier="$1"
    local port="${2:-15151}"

    cd "$SERVER_DIR" || { print_error "No se puede acceder a $SERVER_DIR"; exit 1; }

    local world_id=""
    # Si el token coincide con un ID existente, úsalo directamente
    if world_exists "$world_identifier"; then
        world_id="$world_identifier"
    else
        # Intentar buscar por nombre (soporta espacios)
        if world_id="$(get_world_id_by_name "$world_identifier")"; then
            :
        else
            print_error "No existe un mundo con nombre o ID '$world_identifier'"
            exit 1
        fi
    fi

    print_status "Iniciando mundo ID: $world_id en puerto: $port"
    # ejecutar en primer plano (el --no-exit está basado en tu binario original)
    "$SERVER_BIN" --load "$world_id" --port "$port" --no-exit
}

list_worlds() {
    cd "$SERVER_DIR" || { print_error "No se puede acceder a $SERVER_DIR"; exit 1; }
    "$SERVER_BIN" --list 2>/dev/null || {
        print_warn "No se pudo obtener la lista con '$SERVER_BIN --list'. Puede que el binario devuelva error o requiera entorno."
    }
}

delete_world() {
    if [[ -z "${1:-}" ]]; then
        print_error "Se requiere el ID o nombre del mundo a eliminar."
        exit 1
    fi
    local world_identifier="$1"
    cd "$SERVER_DIR" || { print_error "No se puede acceder a $SERVER_DIR"; exit 1; }

    local world_id=""
    if world_exists "$world_identifier"; then
        world_id="$world_identifier"
    else
        if world_id="$(get_world_id_by_name "$world_identifier")"; then
            :
        else
            print_error "No existe un mundo con nombre o ID '$world_identifier'"
            exit 1
        fi
    fi

    read -r -p "¿Estás seguro de que quieres eliminar el mundo ID: $world_id? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Eliminación cancelada."
        exit 0
    fi

    print_status "Eliminando mundo ID: $world_id"
    "$SERVER_BIN" --delete "$world_id" --force
    print_status "El mundo $world_id ha sido eliminado (si el binario lo confirmó)."
}

# ---------------------------
# Main
# ---------------------------
main() {
    determine_worlds_dir
    check_prereqs

    case "${1:-help}" in
        create)
            shift || true
            create_world "$@"
            ;;
        start)
            shift || true
            start_world "$@"
            ;;
        list)
            list_worlds
            ;;
        delete)
            shift || true
            delete_world "$@"
            ;;
        help|--help|-h|*)
            show_help
            ;;
    esac
}

# Ejecutar main con todos los argumentos
main "$@"
