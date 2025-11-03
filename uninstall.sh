#!/bin/bash

# Uninstallation process begins
if sudo -v; then
  echo "Authentication succeeded."
else
  echo "Authentication failed."
  exit 1
fi

set -a
source ./.env
set +a

COMPOSE_DIR=./compose

mapfile -t COMPOSE_FILES < <(find "$COMPOSE_DIR" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) | sort)

if [ ${#COMPOSE_FILES[@]} -eq 0 ]; then
  echo "No compose files found in $COMPOSE_DIR"
  exit 1
fi

echo "Select honeypot to remove (Enter=1)"
for i in "${!COMPOSE_FILES[@]}"; do
  fname=$(basename "${COMPOSE_FILES[$i]}")
  name="${fname%.*}"
  printf "  %2d) %-12s -> %s\n" "$((i+1))" "$name" "${COMPOSE_FILES[$i]}"
done

read -p "Selection (number or name): " INPUT
[ -z "$INPUT" ] && INPUT=1

if [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  idx=$((INPUT-1))
  if [ $idx -lt 0 ] || [ $idx -ge ${#COMPOSE_FILES[@]} ]; then
    echo "Error: invalid number: $INPUT"
    exit 1
  fi
  SELECTED_COMPOSE_FILE="${COMPOSE_FILES[$idx]}"
else
  MATCHED=""
  for f in "${COMPOSE_FILES[@]}"; do
    n=$(basename "$f"); n="${n%.*}"
    if [ "$n" = "$INPUT" ]; then
      MATCHED="$f"; break
    fi
  done
  if [ -z "$MATCHED" ]; then
    echo "Error: compose for '$INPUT' not found under $COMPOSE_DIR"
    exit 1
  fi
  SELECTED_COMPOSE_FILE="$MATCHED"
fi

if [ ! -f "$SELECTED_COMPOSE_FILE" ]; then
  echo "Compose file not found: $SELECTED_COMPOSE_FILE"
  exit 1
fi

echo
echo "Deleting services with Docker Compose..."
echo

if ! docker compose -f "$SELECTED_COMPOSE_FILE" down --rmi all --volumes --remove-orphans; then
  echo "Error: docker compose down failed."
  exit 1
fi

echo
echo "Handling data backup..."
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="$(basename "$SCRIPT_DIR")"

INSTALL_DATE_FILE=".install_date"
TODAY=$(date +"%Y%m%d")
TIMENOW=$(date +"%H%M%S")

if [ -f "$INSTALL_DATE_FILE" ]; then
  INSTALL_DATE=$(cat "$INSTALL_DATE_FILE")
else
  INSTALL_DATE="unknown"
fi

PERIOD_DIR="${INSTALL_DATE}-${TODAY}-${TIMENOW}"

ARCHIVE_BASE="../archive/${PROJECT_NAME}"
TARGET_DIR="${ARCHIVE_BASE}/${PERIOD_DIR}"

if [ -d "./data" ]; then
  mkdir -p "$TARGET_DIR"
  echo "Copying ./data → ${TARGET_DIR}/data"
  cp -a ./data "${TARGET_DIR}/data"
  echo "Data copied successfully."
else
  echo "No ./data directory found. Skipping."
fi

echo
echo "Uninstallation complete."
