#!/usr/bin/env bash
#
# onbox installer for Linux systems using systemd user services.
# Usage: ./install.sh
#

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly BIN_DIR="${ONBOX_BIN_DIR:-$HOME/.local/bin}"
readonly SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
readonly CLI_SOURCE="$SCRIPT_DIR/onbox"
readonly SERVICE_SOURCE="$SCRIPT_DIR/onbox-mount.service"

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

printf 'Installing onbox...\n'

[[ "$(uname -s)" == "Linux" ]] || fail "onbox mount support requires Linux and systemd."
(( EUID != 0 )) || fail "Do not run this installer with sudo; it installs a per-user service."

for command_name in rclone systemctl install sed mktemp mv; do
    command -v "$command_name" >/dev/null 2>&1 ||
        fail "Required command not found: $command_name"
done

readonly RCLONE_PATH="$(command -v rclone)"
[[ "$RCLONE_PATH" == /* ]] || fail "Could not resolve rclone to an absolute executable path."
if [[ "$RCLONE_PATH" =~ [[:cntrl:]] || "$RCLONE_PATH" == *\"* || "$RCLONE_PATH" == *\\* ]]; then
    fail "The rclone path contains characters unsupported by systemd: $RCLONE_PATH"
fi

[[ -f "$CLI_SOURCE" ]] || fail "Missing source file: $CLI_SOURCE"
[[ -f "$SERVICE_SOURCE" ]] || fail "Missing source file: $SERVICE_SOURCE"

if ! systemctl --user show-environment >/dev/null 2>&1; then
    fail "The systemd user manager is unavailable. Log in normally and rerun the installer."
fi

install -d -m 0755 -- "$BIN_DIR" "$SYSTEMD_USER_DIR"
install -m 0755 -- "$CLI_SOURCE" "$BIN_DIR/onbox"

# Pin ExecStart to the executable found now; a user manager may have a
# different PATH from the invoking shell. Escape systemd specifiers first,
# then escape the value for use as a sed replacement.
systemd_rclone_path="${RCLONE_PATH//%/%%}"
systemd_rclone_path="${systemd_rclone_path//\\/\\\\}"
systemd_rclone_path="${systemd_rclone_path//\"/\\\"}"
service_exec="\"$systemd_rclone_path\""
sed_replacement="${service_exec//\\/\\\\}"
sed_replacement="${sed_replacement//&/\\&}"
sed_replacement="${sed_replacement//|/\\|}"
service_tmp="$(mktemp "$SYSTEMD_USER_DIR/.onbox-mount.service.XXXXXX")"
trap 'rm -f -- "${service_tmp:-}"' EXIT
if ! sed "s|/usr/bin/env rclone|$sed_replacement|" "$SERVICE_SOURCE" > "$service_tmp"; then
    fail "Could not render the systemd service."
fi
chmod 0644 -- "$service_tmp"
mv -f -- "$service_tmp" "$SYSTEMD_USER_DIR/onbox-mount.service"
trap - EXIT

systemctl --user daemon-reload

printf '\nInstallation complete.\n'
printf '  CLI:     %s\n' "$BIN_DIR/onbox"
printf '  Service: %s\n' "$SYSTEMD_USER_DIR/onbox-mount.service"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        printf '\nWarning: %s is not in PATH. Add it to your shell profile, for example:\n' "$BIN_DIR"
        printf '  export PATH="%s:$PATH"\n' "$BIN_DIR"
        ;;
esac

if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
    printf '\nWarning: no fusermount helper was found. push and ls will work, but mount may require a FUSE package.\n'
fi

printf '\nNext steps:\n'
printf '  1. Configure a Google Drive remote named drive: rclone config\n'
printf '  2. Verify it: rclone lsd drive:\n'
printf '  3. Upload a file: onbox push FILE\n'
