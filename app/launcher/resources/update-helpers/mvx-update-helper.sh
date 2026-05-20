#!/bin/bash
# mvx-update-helper.sh — External helper for in-app self-update.
# Called by mvx to replace the running app bundle and relaunch.
#
# Usage: mvx-update-helper.sh <extracted_app_path> <current_app_path> <pid_to_wait_for>
#
# This script:
#   1. Waits for the running mvx process (identified by PID) to exit.
#   2. Backs up the old app bundle.
#   3. Moves the new app bundle into the same path.
#   4. Removes the old backup after confirming the new app is in place.
#   5. Clears quarantine attributes.
#   6. Relaunches the new mvx app.

set -euo pipefail

EXTRACTED_APP="$1"
CURRENT_APP="$2"
PID_TO_WAIT="$3"

if [ -z "$EXTRACTED_APP" ] || [ -z "$CURRENT_APP" ] || [ -z "$PID_TO_WAIT" ]; then
    echo "Usage: mvx-update-helper.sh <extracted_app_path> <current_app_path> <pid>" >&2
    exit 1
fi

PARENT_DIR="$(dirname "$CURRENT_APP")"
NEW_APP_PATH="$PARENT_DIR/mvx.app"

# Wait for the old process to exit
echo "mvx-update-helper: Waiting for process $PID_TO_WAIT to exit..."
while kill -0 "$PID_TO_WAIT" 2>/dev/null; do
    sleep 0.5
done
echo "mvx-update-helper: Process $PID_TO_WAIT has exited."

# Atomic replacement: backup old app first
BACKUP_APP="$CURRENT_APP.backup.$(date +%s)"
if [ -d "$CURRENT_APP" ]; then
    mv "$CURRENT_APP" "$BACKUP_APP"
fi

# Move new app into place
if ! mv "$EXTRACTED_APP" "$NEW_APP_PATH"; then
    echo "mvx-update-helper: Failed to move new app into place." >&2
    if [ -d "$BACKUP_APP" ]; then
        mv "$BACKUP_APP" "$CURRENT_APP"
        echo "mvx-update-helper: Restored previous version from backup." >&2
    fi
    exit 1
fi

# Remove backup only after new app is confirmed in place
if [ -d "$BACKUP_APP" ]; then
    rm -rf "$BACKUP_APP"
fi

# Clear quarantine
xattr -cr "$NEW_APP_PATH" 2>/dev/null || true

# Relaunch
open "$NEW_APP_PATH"

echo "mvx-update-helper: Update complete. Launched $NEW_APP_PATH"
exit 0