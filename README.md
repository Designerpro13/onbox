# onbox

A small Linux command-line wrapper around [rclone](https://rclone.org/) for explicit Google Drive uploads and an optional systemd-managed FUSE mount.

## What it does

- `onbox push <file>` uploads one regular file directly with `rclone copy` and live progress.
- `onbox ls` lists files visible through the configured `drive:` remote.
- `onbox mount` mounts `drive:` at `~/Drive` using a systemd user service.
- `onbox umount` stops that service and unmounts the drive.

A push does **not** require or start the mount. The upload runs in the foreground, so closing the terminal interrupts it. The optional mount service is independent of the terminal, but it remains active until stopped or until the user systemd manager exits; there is no automatic inactivity timeout.

## Requirements and platform support

onbox currently supports **Linux systems with systemd user services**. The installer intentionally rejects macOS and root execution because the mount implementation is a per-user systemd service. macOS users can use rclone directly.

Required:

- Bash
- rclone
- systemd with a working user manager
- Standard Linux utilities (`install`, `mountpoint`, `realpath`, and coreutils)

A FUSE package is also required for `onbox mount`; `push` and `ls` do not need FUSE. For example, on Ubuntu/Debian:

```bash
sudo apt update
sudo apt install rclone fuse3
```

## Install

```bash
git clone https://github.com/Designerpro13/onbox.git
cd onbox
bash install.sh
```

The installer uses the files in its own directory, so it can be invoked from another working directory. It installs only for the current user and must not be run with `sudo`:

- CLI: `~/.local/bin/onbox`
- Service: `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/onbox-mount.service`

If `~/.local/bin` is not in `PATH`, the installer prints the shell configuration line to add. `ONBOX_BIN_DIR` may be set to choose another user-writable CLI directory.

The installed service records the absolute `rclone` executable found during installation. Rerun the installer if rclone moves.

## Configure rclone

Create a Google Drive remote named exactly `drive`:

```bash
rclone config
rclone lsd drive:
```

Choose the Google Drive backend and an OAuth scope suitable for your use. onbox does **not** select or enforce a scope. The restricted `drive.file` scope limits access to files created or explicitly opened by the application and may prevent listing or managing existing Drive content. Features such as broad existing-file access or some Shared Drive workflows can require a broader scope; review Google's and rclone's scope descriptions before granting it.

The remote name is currently fixed as `drive:` in both the CLI and service. Creating a separate rclone `crypt` remote does not make onbox use it automatically.

## Usage

```bash
# Upload one file to the root of drive:
onbox push ./report.pdf

# List files visible through drive:
onbox ls

# Optional FUSE mount
onbox mount
ls ~/Drive
onbox umount

# Help
onbox help
```

`push` accepts exactly one readable regular file. It canonicalizes the local path before passing it to rclone so a filename cannot be mistaken for a flag or remote.

## How it works

### Direct upload

```text
onbox push FILE -> validate and canonicalize FILE -> rclone copy FILE drive:
```

No mount or background process is created. A successful return means rclone completed the foreground copy.

### Optional mount

```text
onbox mount -> systemctl --user start onbox-mount.service
             -> rclone mount drive: ~/Drive

onbox umount -> systemctl --user stop onbox-mount.service
```

The service creates `~/Drive`, runs unprivileged as the current user, applies a restrictive `0077` umask, and asks rclone to shut down cleanly with `SIGINT`. It uses VFS write caching, a 12-hour directory cache, and 30-second polling.

## Security notes

- onbox never runs rclone as root and the installer does not use `sudo`.
- OAuth permissions are determined entirely by your rclone configuration; verify the selected scope yourself.
- rclone's configuration contains sensitive OAuth material. Its default obfuscation is not equivalent to secure encryption. Restrict file permissions and use rclone's configuration-password feature if appropriate. Locate the active file with `rclone config file`.
- A mounted remote exposes accessible Drive content to processes running as your user. Unmount it when it is not needed.
- VFS writes may be cached locally by rclone, normally below the user cache directory. Protect the local account and disk accordingly.
- onbox does not provide content encryption. To use an rclone `crypt` remote today, invoke rclone directly or modify the configured remote in both `onbox` and `onbox-mount.service` before installation.
- Do not enable systemd lingering merely to make uploads survive logout: uploads are foreground operations and lingering only affects the optional mount service.

## Service lifecycle and logout

The mount survives closing its launching terminal because systemd owns it. On many systems the user manager—and therefore the mount—stops at logout. Administrators can enable lingering with:

```bash
loginctl enable-linger "$USER"
```

Lingering keeps user services running without an active login, which increases the time the remote stays mounted. Enable it only if that behavior is wanted.

## Troubleshooting

Check configuration and direct access:

```bash
rclone config file
rclone lsd drive:
```

Inspect mount failures:

```bash
systemctl --user status onbox-mount.service
journalctl --user -u onbox-mount.service -n 50
```

Check the mount and stop it normally:

```bash
mountpoint ~/Drive
onbox umount
```

If rclone was killed and left an orphaned FUSE mount, try the unprivileged helper available on the system:

```bash
fusermount3 -u ~/Drive
# Older FUSE installations may use: fusermount -u ~/Drive
```

If the service cannot find rclone after rclone was moved or replaced, rerun `bash install.sh` so its absolute path is regenerated.

## Project layout

```text
onbox/
├── onbox                  # Bash CLI
├── onbox-mount.service    # systemd user-service source
├── install.sh             # Per-user installer
├── architecture.md        # Design and security details
├── README.md
└── LICENSE
```

## Limitations

- Linux/systemd only
- One fixed remote (`drive:`) and mount point (`~/Drive`)
- One file per `push`; no synchronization or directory upload interface
- No automatic unmount timer
- No detached/resumable upload management
- No automatic crypt-remote selection

Use rclone directly for synchronization, custom destinations, detached execution, or advanced filtering.

## Uninstall

Stop the mount first, then remove the installed files:

```bash
onbox umount
rm -f ~/.local/bin/onbox
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/onbox-mount.service"
systemctl --user daemon-reload
```

Adjust the CLI path if `ONBOX_BIN_DIR` was used.

## Contributing

Test changes on a Linux system with systemd user services. For mount bugs, include:

```bash
systemctl --user status onbox-mount.service
journalctl --user -u onbox-mount.service -n 50
```

## License

MIT — see [LICENSE](LICENSE).
