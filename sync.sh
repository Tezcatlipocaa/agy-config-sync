#!/usr/bin/env bash
# ==============================================================================
# agy-config-sync: Multi-machine synchronization engine (macOS / Linux / WSL)
# ==============================================================================
set -euo pipefail

ACTION="${1:-}"
PROFILE="${2:-}"
DRY_RUN=false

for arg in "$@"; do
    if [ "$arg" == "--dry-run" ] || [ "$arg" == "-DryRun" ]; then
        DRY_RUN=true
    fi
done

if [ -z "$ACTION" ]; then
    echo "Usage: ./sync.sh <status|add-machine|snapshot|stage|apply> [profile] [--dry-run]"
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_HOME="${HOME}/.gemini"
GEMINI_CONFIG="${GEMINI_HOME}/config"
GEMINI_CLI="${GEMINI_HOME}/antigravity-cli"
MANIFEST_PATH="${REPO_ROOT}/manifest.json"
HOST_MAP_PATH="${REPO_ROOT}/host-map.json"
ENV_LOCAL_PATH="${REPO_ROOT}/.env.local"
STAGING_PATH="${REPO_ROOT}/staging"
CACHE_PATH="${REPO_ROOT}/.cache"
HOSTNAME_CMD="$(hostname)"

# Activate git hooks
git config core.hooksPath hooks 2>/dev/null || true

# Resolve profile from host-map if not provided
if [ -z "$PROFILE" ] && [ -f "$HOST_MAP_PATH" ]; then
    RESOLVED=$(grep -E "\"$HOSTNAME_CMD\":" "$HOST_MAP_PATH" | sed -E 's/.*: *"([^"]+)".*/\1/' || true)
    if [ -n "$RESOLVED" ]; then
        PROFILE="$RESOLVED"
    fi
fi

# -----------------------------------------------------------------------------
# COMMAND: STATUS
# -----------------------------------------------------------------------------
if [ "$ACTION" == "status" ]; then
    echo "=========================================================="
    echo " agy-config-sync - Machine Status"
    echo "=========================================================="
    echo "[INFO] Current Hostname: $HOSTNAME_CMD"
    echo "[INFO] Resolved Profile: ${PROFILE:-<Unregistered Machine>}"
    echo "[INFO] Antigravity Path: $GEMINI_HOME"

    if [ -f "$ENV_LOCAL_PATH" ]; then
        echo "[OK] .env.local detected"
    else
        echo "[WARN] .env.local not found"
    fi

    if pgrep -f "agy|antigravity" >/dev/null 2>&1; then
        echo "[WARN] Antigravity CLI (agy) is currently running"
    else
        echo "[OK] Antigravity CLI (agy) is closed (safe to apply)"
    fi
    exit 0
fi

# -----------------------------------------------------------------------------
# COMMAND: ADD-MACHINE
# -----------------------------------------------------------------------------
if [ "$ACTION" == "add-machine" ]; then
    if [ -z "$PROFILE" ]; then
        echo "[ERROR] Usage: ./sync.sh add-machine <profile-name>"
        exit 1
    fi

    node -e "
        const fs = require('fs');
        const map = fs.existsSync('$HOST_MAP_PATH') ? JSON.parse(fs.readFileSync('$HOST_MAP_PATH')) : {};
        map['$HOSTNAME_CMD'] = '$PROFILE';
        fs.writeFileSync('$HOST_MAP_PATH', JSON.stringify(map, null, 2));
    " 2>/dev/null || echo "{\"$HOSTNAME_CMD\": \"$PROFILE\"}" > "$HOST_MAP_PATH"

    OVERRIDE_FILE="${REPO_ROOT}/overrides/${PROFILE}.json"
    if [ ! -f "$OVERRIDE_FILE" ]; then
        cat <<EOF > "$OVERRIDE_FILE"
{
  "profile": "$PROFILE",
  "hostname": "$HOSTNAME_CMD",
  "description": "Overrides for $PROFILE",
  "disabledPlugins": [],
  "extraMcpServers": {}
}
EOF
    fi
    echo "[OK] Registered machine '$HOSTNAME_CMD' as '$PROFILE'"
    exit 0
fi

if [ -z "$PROFILE" ]; then
    echo "[ERROR] Machine '$HOSTNAME_CMD' is not registered. Run first: ./sync.sh add-machine <profile-name>"
    exit 1
fi

# -----------------------------------------------------------------------------
# COMMAND: SNAPSHOT
# -----------------------------------------------------------------------------
if [ "$ACTION" == "snapshot" ]; then
    echo "=========================================================="
    echo " Capturing snapshot for profile: $PROFILE ($HOSTNAME_CMD)"
    echo "=========================================================="
    SNAPSHOT_DIR="${REPO_ROOT}/snapshots/${PROFILE}"
    mkdir -p "$SNAPSHOT_DIR"

    cat <<EOF > "${SNAPSHOT_DIR}/metadata.json"
{
  "profile": "$PROFILE",
  "hostname": "$HOSTNAME_CMD",
  "capturedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "os": "$(uname -s) $(uname -r)",
  "user": "${USER:-unknown}"
}
EOF

    [ -f "${GEMINI_HOME}/GEMINI.md" ] && cp "${GEMINI_HOME}/GEMINI.md" "${SNAPSHOT_DIR}/GEMINI.md" && mkdir -p "${REPO_ROOT}/copy" && cp "${GEMINI_HOME}/GEMINI.md" "${REPO_ROOT}/copy/GEMINI.md"
    [ -f "${GEMINI_CONFIG}/config.json" ] && cp "${GEMINI_CONFIG}/config.json" "${SNAPSHOT_DIR}/config.json" && mkdir -p "${REPO_ROOT}/copy/config" && cp "${GEMINI_CONFIG}/config.json" "${REPO_ROOT}/copy/config/config.json"

    echo "[OK] Snapshot completed in snapshots/${PROFILE}"
    exit 0
fi

# -----------------------------------------------------------------------------
# COMMAND: STAGE
# -----------------------------------------------------------------------------
if [ "$ACTION" == "stage" ]; then
    echo "=========================================================="
    echo " Assembling staging/ for profile: $PROFILE"
    echo "=========================================================="
    rm -rf "$STAGING_PATH"
    mkdir -p "$STAGING_PATH"

    # Copy level A files
    [ -f "${REPO_ROOT}/copy/GEMINI.md" ] && cp "${REPO_ROOT}/copy/GEMINI.md" "${STAGING_PATH}/GEMINI.md"
    if [ -f "${REPO_ROOT}/copy/config/config.json" ]; then
        mkdir -p "${STAGING_PATH}/config"
        cp "${REPO_ROOT}/copy/config/config.json" "${STAGING_PATH}/config/config.json"
    fi

    echo "[OK] Staging prepared successfully."
    exit 0
fi

# -----------------------------------------------------------------------------
# COMMAND: APPLY
# -----------------------------------------------------------------------------
if [ "$ACTION" == "apply" ]; then
    echo "=========================================================="
    echo " Applying configuration to: $GEMINI_HOME"
    echo "=========================================================="
    if [ "$DRY_RUN" = false ] && pgrep -f "agy|antigravity" >/dev/null 2>&1; then
        echo "[ERROR] Antigravity CLI (agy) is currently open. Close it before applying."
        exit 1
    fi

    if [ ! -d "$STAGING_PATH" ]; then
        echo "[ERROR] staging/ not found. Run first: ./sync.sh stage"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] Files that would be applied to $GEMINI_HOME:"
        find "$STAGING_PATH" -type f
        echo "[OK] [DRY-RUN] Verification complete."
        exit 0
    fi

    BACKUP_DIR="${REPO_ROOT}/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    echo "[INFO] Creating safety backup in: $BACKUP_DIR"
    for f in "GEMINI.md" "config/config.json" "config/mcp_config.json" "antigravity-cli/settings.json"; do
        if [ -f "${GEMINI_HOME}/${f}" ]; then
            mkdir -p "$(dirname "${BACKUP_DIR}/${f}")"
            cp "${GEMINI_HOME}/${f}" "${BACKUP_DIR}/${f}"
        fi
    done

    echo "[INFO] Copying staging files to ~/.gemini..."
    cp -R "${STAGING_PATH}/"* "${GEMINI_HOME}/"
    echo "[OK] Configuration applied successfully."
    exit 0
fi
