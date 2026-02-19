# onbox

**Minimal, secure Google Drive CLI wrapper built on rclone.**

A frictionless command-line tool for uploading files to Google Drive without the bloat of sync daemons, file watching, or always-on background processes. Designed for manual workflows that respect your storage and security.

---

## Features

- **`onbox push <file>`** — Upload files with live progress
- **Auto-mount on demand** — Automatically mounts Google Drive when needed
- **Background service** — Runs via systemd, survives terminal close
- **Smart unmount** — Auto-unmounts after 5 minutes of inactivity
- **Minimal OAuth** — Uses only `drive.file` scope
- **No sync daemon** — No persistent background processes
- **Clean lifecycle** — Proper service management, no shell hacks

---

## Quick Start

### Prerequisites

```bash
# Ubuntu 22.04+
sudo apt install rclone

# macOS
brew install rclone
```

### Install

```bash
git clone https://github.com/<you>/onbox.git
cd onbox

sudo cp bin/onbox /usr/local/bin/
sudo chmod +x /usr/local/bin/onbox

mkdir -p ~/.config/systemd/user
cp systemd/onbox-mount.service ~/.config/systemd/user/
systemctl --user daemon-reload
```

### Configure rclone

```bash
rclone config
```

- **Type:** `drive`
- **Scope:** `drive.file` (recommended)
- **Name remote:** `drive`

Test:

```bash
rclone ls drive:
```

---

## Usage

### Upload a file

```bash
onbox push myfile.txt
```

The script will:
1. Check if Google Drive is mounted
2. Auto-mount if needed (background)
3. Upload the file
4. Schedule auto-unmount after inactivity

### List remote files

```bash
onbox ls
```

### Manual mount/unmount

```bash
onbox mount
onbox umount
```

---

## How It Works

**Workflow:**
```
onbox push file.txt
  ↓
Check if ~/Drive is mounted?
  ↓ (if not)
Start systemd service (background)
  ↓
Upload via rclone
  ↓
Start 5-min inactivity timer
  ↓ (if idle)
Auto-unmount
```

**Why systemd?**
- Decoupled from terminal — survives logout
- Proper lifecycle — no `&` background hacks
- Clean recovery — auto-restart on failure
- Standard — uses OS-native service management

---

## Architecture

```
onbox/
├── bin/onbox                    # Main CLI script
├── systemd/
│   └── onbox-mount.service     # systemd user service
├── docs/
│   └── architecture.md          # Deep dive
├── README.md
└── LICENSE
```

**Key design choices:**
- Mount point: `~/Drive`
- Service: systemd user service (not system-wide)
- Cache: 12-hour directory cache
- Auto-unmount: 300 seconds inactivity timeout
- Scope: `drive.file` (only files you create)

---

## Security Model

✅ **What we do right:**
- Minimal OAuth scope — no read-all permissions
- No persistent daemon — smaller attack surface
- Mount runs unprivileged — as your user
- No auto-sync — you decide what's uploaded
- Config isolated — `~/.config/rclone/rclone.conf`

⚠️ **What you should know:**
- rclone credentials stored in plaintext (use `rclone config` encryption)
- Google Drive is eventually consistent — small sync delays normal
- Mount can be slow on large folders (use for upload, not browsing)

**Optional: Enable encryption**

Use rclone's `crypt` remote for end-to-end encryption:

```bash
rclone config
# Create "crypt" remote pointing to "drive:"
onbox push file.txt  # Will encrypt automatically
```

---

## Optional: Survive Logout

By default, the mount stops when you log out. To keep it alive:

```bash
loginctl enable-linger $USER
```

Now systemd mounts persist across login sessions.

---

## Troubleshooting

**Mount fails to start**
```bash
systemctl --user status onbox-mount.service
systemctl --user start onbox-mount.service
```

**Check if mounted**
```bash
mountpoint ~/Drive
ls ~/Drive
```

**Manual unmount stuck**
```bash
sudo fusermount -u ~/Drive
```

**Reset service**
```bash
systemctl --user reset-failed onbox-mount.service
```

---

## Philosophy

This tool is **not** a Dropbox clone. It favors:

- **Explicit control** over magic
- **Manual workflows** over continuous sync
- **Minimal scope** over maximum features
- **CLI-first** over GUI clutter

Use it for uploading, archiving, or backing up files. Don't use it for folder sync or file sharing.

---

## Roadmap

Future improvements:
- [ ] Config file support (timeout, mount point)
- [ ] Shell completion (bash, zsh)
- [ ] Encryption-mode toggle (`--crypt`)
- [ ] Install script
- [ ] Version flag (`--version`)
- [ ] Idle detection based on network traffic (not just open files)

---

## License

MIT — Use freely, modify, distribute.

---

## Contributing

Found a bug? Have ideas?

1. Test on Ubuntu 22.04+
2. Open an issue or PR
3. Include `systemctl --user status onbox-mount.service` output if mount-related

---

## FAQ

**Q: Why not use Google Drive's official CLI?**  
A: They don't have one. This is minimal, open, and rclone-based.

**Q: Can I use this with Shared Drives?**  
A: Yes. During `rclone config`, enable "Team Drive" and point to your shared drive ID.

**Q: Does this sync my folders?**  
A: No. It's upload-only, by design. Use `rclone sync` if you want bidirectional sync.

**Q: What if I close the terminal while uploading?**  
A: The upload continues. systemd keeps the mount alive. You're good.

**Q: Can I have multiple mounts?**  
A: Yes. Create separate services: `onbox-mount-drive1.service`, `onbox-mount-drive2.service`, etc.

---

**Made with ❤️ for minimal workflows.**
