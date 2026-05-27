#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

GLOBALS_FILE="${GLOBALS_FILE:-$SCRIPT_DIR/globals.env}"
INSTANCES_DIR="${INSTANCES_DIR:-$SCRIPT_DIR/instances}"

COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/compose.yml}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
GEN_SCRIPT="$SCRIPT_DIR/gen_instances_files.py"
CSV_FILE="${CSV_FILE:-${SCRIPT_DIR}/inventory.csv}"


usage() {
  cat <<'EOF'
Usage:
  ./deploy.sh up [USER_NAME]        Generate env files, hash Node-RED passwords, deploy all or one instance
  ./deploy.sh down [USER_NAME]      Stop/remove all or one instance
  ./deploy.sh config [USER_NAME]    Render Docker Compose config for all or one instance
  ./deploy.sh generate              Generate instances/*.env only
  ./deploy.sh hash [USER_NAME]      Generate/update NODE_RED_PASSWORD_HASH only

Environment overrides:
  CSV_FILE=inventory.csv
  GLOBALS_FILE=globals.env
  INSTANCES_DIR=instances
  COMPOSE_FILE=compose.yml
  BCRYPT_ROUNDS=8
  KEEP_VOLUMES=0   For "down": 0 removes named volumes; 1 keeps them
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

keep_volumes_enabled() {
  case "${KEEP_VOLUMES:-0}" in
    1)
      return 0
+      ;;
    0)
      return 1
      ;;
    *)
      echo "Invalid KEEP_VOLUMES value: ${KEEP_VOLUMES}" >&2
      echo "Use KEEP_VOLUMES=1 to keep volumes or KEEP_VOLUMES=0 to remove them." >&2
      exit 2
      ;;
  esac
}

get_env_value() {
  local env_file="$1"
  local key="$2"

  "$PYTHON_BIN" - "$env_file" "$key" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
wanted = sys.argv[2]


if not path.exists():
    sys.exit(1)

for raw_line in path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    if key.strip() != wanted:
        continue
    value = value.strip()

    if len(value) >= 2 and value[0] == value[-1] == "'":
        value = value[1:-1].replace("\\'", "'").replace("\\\\", "\\")
    elif len(value) >= 2 and value[0] == value[-1] == '"':

        value = bytes(value[1:-1], "utf-8").decode("unicode_escape")
    print(value)
    sys.exit(0)

sys.exit(1)
PY
}

set_env_value() {
  local env_file="$1"
  local key="$2"
  local value="$3"

  "$PYTHON_BIN" - "$env_file" "$key" "$value" <<'PY'
import re

import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]

if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
    raise SystemExit(f"Invalid env key: {key}")

def quote_env_value(value: str) -> str:
    if value == "":
        return "''"
    safe_unquoted = re.match(r"^[A-Za-z0-9_./:@%+-]+$", value) is not None
    if safe_unquoted and "$" not in value:
        return value
    escaped = (
        value.replace("\\", "\\\\")

        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
    )
    return f"'{escaped}'"

new_line = f"{key}={quote_env_value(value)}"
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
updated = False
out = []

for line in lines:
    stripped = line.strip()
    comparable = stripped[len("export "):].strip() if stripped.startswith("export ") else stripped

    if comparable.startswith(f"{key}="):
        if not updated:
            out.append(new_line)
            updated = True
        continue
    out.append(line)

if not updated:
    out.append(new_line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

generate_env_files() {
  require_command "$PYTHON_BIN"

  "$PYTHON_BIN" "$GEN_SCRIPT" --csv "$CSV_FILE" --globals "$GLOBALS_FILE" --out-dir "$INSTANCES_DIR"
}

find_instance_env_files() {
  local selected_user="${1:-}"


  if [[ ! -d "$INSTANCES_DIR" ]]; then
    return 0
  fi


  find "$INSTANCES_DIR" -maxdepth 1 -type f -name '*.env' | sort | while read -r env_file; do
    if [[ -z "$selected_user" ]]; then
      printf '%s\n' "$env_file"
      continue
    fi

    local user_name
    user_name="$(get_env_value "$env_file" USER_NAME || true)"

    if [[ "$user_name" == "$selected_user" ]]; then

      printf '%s\n' "$env_file"
    fi
  done
}

generate_node_red_hash() {
  local image="$1"
  local password="$2"
  local rounds="${BCRYPT_ROUNDS:-8}"

  docker run --rm \
    -e NR_PASSWORD="$password" \
    -e BCRYPT_ROUNDS="$rounds" \
    --entrypoint /bin/sh \
    -w /usr/src/node-red \
    "$image" \
    -c 'node -e '\''
const bcrypt = require("bcryptjs");
const password = process.env.NR_PASSWORD || "";
const rounds = Number(process.env.BCRYPT_ROUNDS || 8);
if (!password) {
  console.error("NR_PASSWORD is empty; refusing to generate a Node-RED password hash.");
  process.exit(2);
}
if (!Number.isInteger(rounds) || rounds < 4 || rounds > 15) {
  console.error("BCRYPT_ROUNDS must be an integer between 4 and 15.");
  process.exit(3);
}
console.log(bcrypt.hashSync(password, rounds));
'\'''
}

hash_env_file() {
  local env_file="$1"
  local user_name user_password node_red_image hash

  user_name="$(get_env_value "$env_file" USER_NAME)"
  user_password="$(get_env_value "$env_file" USER_PASSWORD)"
  node_red_image="$(get_env_value "$env_file" NODE_RED_IMAGE)"

  echo "Hashing Node-RED password for $user_name using $node_red_image"

  hash="$(generate_node_red_hash "$node_red_image" "$user_password")"
  set_env_value "$env_file" NODE_RED_PASSWORD_HASH "$hash"
}

hash_instances() {
  local selected_user="${1:-}"
  require_command docker
  require_command "$PYTHON_BIN"

  local found=0
  while IFS= read -r env_file; do
    found=1
    hash_env_file "$env_file"
  done < <(find_instance_env_files "$selected_user")


  if [[ "$found" -eq 0 ]]; then
    echo "No instance env files found${selected_user:+ for USER_NAME=$selected_user}." >&2
    exit 1
  fi
}

compose_for_instances() {
  local action="$1"
  local selected_user="${2:-}"
  require_command docker

  local found=0
  while IFS= read -r env_file; do
    found=1
    local user_name project_name
    user_name="$(get_env_value "$env_file" USER_NAME)"
    project_name="$(get_env_value "$env_file" COMPOSE_PROJECT_NAME || echo "$user_name")"

    echo "docker compose -p $project_name --env-file $env_file -f $COMPOSE_FILE $action"
    docker compose \
      -p "$project_name" \
      --env-file "$env_file" \
      -f "$COMPOSE_FILE" \
      $action
  done < <(find_instance_env_files "$selected_user")

  if [[ "$found" -eq 0 ]]; then

    echo "No instance env files found${selected_user:+ for USER_NAME=$selected_user}." >&2
    exit 1
  fi
}

main() {
  local command="${1:-up}"

  local selected_user="${2:-}"


  case "$command" in
    up)

      generate_env_files
      hash_instances "$selected_user"
      compose_for_instances "up -d" "$selected_user"
      ;;
    down)
      local down_action="down -v"
      if keep_volumes_enabled; then
          down_action="down"
      fi
      compose_for_instances "$down_action" "$selected_user"
      ;;
    config)
      generate_env_files
      hash_instances "$selected_user"
      compose_for_instances "config" "$selected_user"
      ;;
    generate)
      generate_env_files
      ;;
    hash)
      generate_env_files
      hash_instances "$selected_user"
      ;;
    -h|--help|help)
      usage

      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
