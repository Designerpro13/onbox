# Architecture

## Scope

onbox is a Linux/Bash wrapper around rclone with two deliberately separate workflows:

1. A foreground, direct upload to `drive:`.
2. An optional Google Drive FUSE mount managed by a systemd user service.

It is not a synchronization daemon, file watcher, detached upload manager, or cross-platform service abstraction.

## Repository layout

```text
onbox/
├── onbox
├── onbox-mount.service
├── install.sh
├── architecture.md
├── README.md
└── LICENSE
```

The repository is flat. The installer resolves source files relative to its own location rather than the caller's working directory.

## Components

### CLI (`onbox`)

The Bash CLI parses `push`, `ls`, `mount`, and `umount` commands and validates command-specific dependencies.

For `push`, it:

1. Requires exactly one readable regular file.
2. Resolves the file to an absolute canonical path, preventing a leading dash or colon-containing relative name from being interpreted by rclone as an option or remote.
3. Executes `rclone copy ABSOLUTE_PATH drive: --progress` in the foreground.
4. Returns rclone's success or failure to the caller.

The direct upload does not use `~/Drive` and does not start systemd. Closing the terminal can interrupt rclone.

For `mount`, the CLI starts `onbox-mount.service` and polls for up to 15 seconds for `~/Drive` to become a mount point. Fixed sleeps are avoided because mount initialization time varies. For `umount`, the CLI asks systemd to stop the service.

### Installer (`install.sh`)

The installer is intentionally per-user. It:

- Rejects non-Linux platforms and execution as root.
- Checks for rclone, systemctl, installation utilities, and a reachable systemd user manager.
- Installs the CLI in `${ONBOX_BIN_DIR:-$HOME/.local/bin}` with mode `0755`.
- Installs the service in `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user` with mode `0644`.
- Replaces `/usr/bin/env rclone` in the source unit with the absolute executable found by `command -v rclone`, properly escaping the path for systemd and the rendering step.
- Reloads the user manager without enabling or starting a persistent service.

Using the discovered executable avoids assumptions such as `/usr/bin/rclone`, which fail for manually installed, distribution-independent, or alternate-prefix installations. The source service retains `/usr/bin/env rclone` so it remains readable and usable for development; installed copies are pinned.

### Mount service (`onbox-mount.service`)

The unit is a systemd **user** service. It must not contain `User=` and does not require root.

Relevant behavior:

```ini
Type=simple
UMask=0077
ExecStartPre=/usr/bin/mkdir -p %h/Drive
ExecStart=/path/discovered/by/installer/rclone mount drive: %h/Drive ...
KillSignal=SIGINT
Restart=on-failure
```

No hard-coded `fusermount` path is used. On a normal service stop, systemd sends `SIGINT` to rclone, which performs its shutdown and unmount handling. This avoids assuming either `/bin/fusermount` or a particular FUSE major version.

Mount options:

- `--vfs-cache-mode writes`: cache write operations as required by rclone's VFS layer.
- `--dir-cache-time 12h`: retain directory metadata for up to 12 hours.
- `--poll-interval 30s`: poll supported remotes for changes.

The service stays active until stopped, the user manager exits, or it fails. There is no inactivity timer. `Restart=on-failure` applies to unexpected failures, not an explicit `systemctl stop`.

## Data flows

### Upload

```text
User terminal
    |
    v
onbox push FILE
    | validate + realpath
    v
rclone copy FILE drive:
    |
    v
Google Drive API
```

The terminal owns the CLI and rclone process. A terminal hangup or session termination may interrupt the transfer. No claim of detached or resumable execution is made.

### Mount

```text
onbox mount
    |
    v
systemd --user
    |
    v
rclone mount drive: ~/Drive
    |
    +--> FUSE kernel/userspace interface
    |
    +--> Google Drive API
```

systemd, not the invoking shell, owns the mount process. Closing that terminal does not stop the service. Logging out commonly stops the user manager unless lingering is enabled by the user or administrator.

## Security model

### Privilege boundary

Installation and runtime are unprivileged. The installer rejects root to avoid installing files and services into root's home by accident. The unit runs under the user manager and applies `UMask=0077` to files created by the service where the underlying operation honors the process umask.

### OAuth and remote access

onbox does not create credentials or choose OAuth scopes. Those decisions occur in `rclone config`. The fixed `drive:` remote can therefore have narrow or broad access depending on user configuration.

The Google `drive.file` scope is narrower than full Drive access but does not mean “all files owned by this user.” It generally limits access to files created or explicitly opened by the application and can make existing content unavailable. Documentation must not imply that onbox enforces this scope.

### Credentials

rclone's configuration includes sensitive OAuth material. Default token obfuscation should not be described as encryption. Users can locate the active configuration with `rclone config file`, restrict its permissions, and use rclone's configuration-password feature where appropriate.

### Local mount and cache

A mount exposes remote content to processes with the user's permissions. VFS writes can also be cached on local storage. Users should stop unnecessary mounts and apply suitable local account and disk protections.

### Encryption

onbox targets `drive:` literally. Defining a `crypt:` remote does not alter the target and does not enable content encryption automatically. Supporting configurable remotes is a future feature; users needing it now should invoke rclone directly or consistently modify both the CLI and service source.

## Failure handling

### Direct upload failure

The CLI reports rclone's nonzero result and exits nonzero. Because the upload is direct, mount state is irrelevant. Any partial remote result is governed by rclone and the backend; users should inspect the destination before retrying.

### Mount startup failure

The CLI reports failure immediately if `systemctl --user start` fails. If systemd starts the unit but the mount does not become ready within 15 seconds, it directs the user to the journal:

```bash
systemctl --user status onbox-mount.service
journalctl --user -u onbox-mount.service -n 50
```

Typical causes include missing FUSE support, an inaccessible remote, expired credentials, a stale mount, or rclone having moved since installation.

### Orphaned mount

Normal shutdown is always `onbox umount` or `systemctl --user stop onbox-mount.service`. If a killed process leaves an orphaned mount, use the unprivileged helper supplied by the installed FUSE version (`fusermount3 -u` or, on older systems, `fusermount -u`).

## Validation strategy

Static checks:

```bash
bash -n onbox install.sh
systemd-analyze --user verify ./onbox-mount.service
```

Behavioral smoke tests should isolate rclone/systemctl with temporary stub executables before testing against a real account. Manual integration checks are:

```bash
rclone lsd drive:
onbox push /path/to/test-file
onbox mount
mountpoint ~/Drive
onbox umount
```

Real Drive tests transfer data and require user credentials, so they should never be run implicitly by the installer or automated validation.

## Known constraints

- Linux and systemd user services only
- Fixed `drive:` remote and `~/Drive` mount point
- One regular file per push
- Foreground uploads only
- No inactivity-based unmount
- No automatic crypt support
