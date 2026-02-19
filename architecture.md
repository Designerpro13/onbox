# Architecture Overview

## Design Philosophy

**onbox** is intentionally minimal. It wraps rclone to provide a streamlined upload workflow without the complexity of always-on sync daemons or auto-watching file systems.

Core principle: **Explicit > Implicit**

---

## System Architecture

```
┌─────────────────────────────────────────┐
│  User runs: onbox push file.txt        │
└──────────────┬──────────────────────────┘
               │
               ▼
       ┌───────────────┐
       │  onbox (bash) │
       └───────┬───────┘
               │
       ┌───────┴────────────┬──────────────┐
       │                    │              │
       ▼                    ▼              ▼
   Check if       Start systemd     Upload via
   mounted        (if needed)       rclone copy
       │                    │              │
       └────────────────┬───┴──────────────┘
                        │
                        ▼
              Schedule inactivity
              timeout (300s)
                        │
                        ▼
              (if idle) Auto-unmount
```

---

## Components

### 1. CLI Script (`bin/onbox`)

**Language:** Bash  
**Size:** ~100 lines  
**Responsibility:** Argument parsing, mount checking, orchestration

**Key functions:**
- `is_mounted()` — Check if `~/Drive` is accessible
- `start_mount()` — Start systemd service
- `stop_mount()` — Stop systemd service
- `auto_timeout()` — Spawn background timer
- Case statement for `push`, `mount`, `umount`, `ls`

**Why bash?**
- No dependencies (except rclone)
- Ships with every Unix/Linux system
- Clear, easy to audit
- Fast startup

---

### 2. systemd Service (`systemd/onbox-mount.service`)

**Type:** User service (not system-wide)  
**Manages:** rclone mount process  
**Lifecycle:** Decoupled from terminal

**Key directives:**
```ini
Type=simple              # rclone runs foreground
ExecStart=rclone mount  # Runs the FUSE mount
ExecStop=fusermount -u  # Clean unmount
Restart=on-failure      # Auto-recover
```

**Why systemd?**
- Standard service manager (systemd is everywhere post-2015)
- Handles recovery automatically
- Survives terminal close/logout
- Proper signal handling
- User-level (no sudo needed after install)

**Why not:**
- Simple `&` background process → dies with terminal
- `nohup` → harder to manage lifecycle
- Custom daemon → maintenance burden

---

### 3. Mount Point (`~/Drive`)

**Type:** FUSE mount  
**Filesystem:** rclone vfs (virtual filesystem)  
**Purpose:** Present Google Drive as a local folder

**Mount options:**
```bash
--vfs-cache-mode writes      # Cache files during write
--dir-cache-time 12h         # Cache dir listing 12 hours
--poll-interval 30s          # Check for remote changes every 30s
```

---

## Workflow Walkthrough

### Scenario: `onbox push file.txt`

```bash
# 1. Script checks if ~/Drive is a valid mountpoint
is_mounted() {
    mountpoint -q "$MOUNTPOINT"  # Returns 0 if mounted, 1 if not
}

# 2. If not mounted, start the service
if ! is_mounted; then
    mkdir -p "$MOUNTPOINT"
    systemctl --user start onbox-mount.service
    sleep 2  # Wait for mount to stabilize
fi

# 3. Perform the upload
rclone copy "file.txt" "drive:" --progress

# 4. Schedule auto-unmount after inactivity
auto_timeout() {
    (
        sleep 300  # 5 minutes
        if ! lsof +D "$MOUNTPOINT" >/dev/null 2>&1; then
            # No open files in mount → safe to unmount
            systemctl --user stop onbox-mount.service
        fi
    ) &  # Run in background
}
```

**Exit states:**
- ✅ File uploaded, mount will auto-unmount in 5 mins
- ❌ Upload failed → mount stays up for retry
- ✅ Terminal closed → mount persists via systemd

---

## Why This Architecture?

### Problem: Traditional Shell Script Mount

```bash
# ❌ This is what most tutorials show
rclone mount drive: ~/Drive &
cp file.txt ~/Drive/
```

**Issues:**
- Mount dies if terminal closes
- No error recovery
- Zombie processes if killed improperly
- Can't easily unmount from another terminal
- No logging/monitoring

---

### Solution: systemd Management

```bash
# ✅ What we do instead
systemctl --user start onbox-mount.service
cp file.txt ~/Drive/
systemctl --user stop onbox-mount.service
```

**Benefits:**
- Service runs independently
- Survives terminal close
- Automatic restart on failure
- Proper signal handling
- Status/logging integration: `systemctl --user status`
- Works across terminals

---

## Security Considerations

### OAuth Scope: `drive.file`

This is the **most restrictive** Google Drive scope:
- ✅ Can upload files
- ✅ Can read files you created
- ❌ Cannot read all files
- ❌ Cannot share files
- ❌ Cannot delete anything

**Alternative scopes (NOT recommended):**
- `drive` — Full access to all Drive files
- `drive.readonly` — Read everything, write nothing

**Best practice:** Always use `drive.file` for CLI tools.

---

### Credential Storage

rclone stores credentials in:
```
~/.config/rclone/rclone.conf
```

**Plaintext warning:** These are in plaintext. Secure this file:

```bash
chmod 600 ~/.config/rclone/rclone.conf
```

**Better:** Use rclone's built-in encryption:

```bash
rclone config
# When prompted, enable encryption: yes
# Set password for config encryption
```

---

### Temporary Files

Mount operates in `~/.cache/rclone/` for VFS cache:

```bash
ls ~/.cache/rclone/vfs/
```

Files here are temporary and safe. Cleanup:

```bash
rm -rf ~/.cache/rclone/
```

---

## Performance Characteristics

### Mount Startup Time

```
systemctl --user start onbox-mount.service
                       ↓ (1-2 seconds)
Mount ready at ~/Drive
```

Overhead: ~1-2 seconds per `onbox push`

### Upload Speed

Limited by:
1. **rclone copy** speed (typically 10-100 MB/s depending on file size)
2. **Google Drive API** rate limits (1000 files/day per user)
3. **Network connection** (your ISP)

### Memory Usage

rclone mount with these settings:
- Idle: ~50-100 MB
- Active transfer: ~200-500 MB

---

## Failure Modes & Recovery

### Mount Fails to Start

```bash
systemctl --user start onbox-mount.service
Job for onbox-mount.service failed.
```

**Diagnosis:**
```bash
systemctl --user status onbox-mount.service
journalctl --user -u onbox-mount.service -n 20
```

**Common causes:**
- rclone not installed
- `~/Drive` directory permission denied
- Previous mount still active (orphaned)

**Recovery:**
```bash
sudo fusermount -u ~/Drive
systemctl --user reset-failed onbox-mount.service
systemctl --user start onbox-mount.service
```

---

### Upload Interrupted

If terminal closes during upload, the rclone process continues in systemd:

```bash
# Check status
systemctl --user status onbox-mount.service

# If stuck, kill cleanly
systemctl --user stop onbox-mount.service
```

The partial file may exist on Google Drive. Check Drive and re-upload if needed.

---

## Future Enhancements

### 1. Config File Support

```ini
# ~/.config/onbox/config
TIMEOUT=300
MOUNTPOINT=$HOME/Drive
SCOPE=drive.file
```

Benefits: Users customize behavior without editing bash.

### 2. Multiple Remotes

Current setup handles one remote (`drive:`). Extension:

```bash
onbox push --remote backup file.txt
```

Would require multiple service files or dynamic generation.

### 3. Encryption Toggle

```bash
onbox push --crypt file.txt
```

Uses rclone's built-in `crypt` remote for E2E encryption.

### 4. Shell Completion

Bash/Zsh completion for:
```bash
onbox pu<TAB>  →  onbox push
onbox mo<TAB>  →  onbox mount
```

### 5. Idle Detection via Network Activity

Current: `lsof` checks for open files  
Future: Monitor actual drive activity instead

---

## Comparison to Alternatives

| Feature | onbox | rclone sync | Google Drive CLI | Insync |
|---------|-------|------------|------------------|--------|
| Upload files | ✅ | ✅ | ❌ | ✅ |
| Daemon-less | ✅ | ❌ | ✅ | ❌ |
| CLI-only | ✅ | ✅ | ❌ | ❌ |
| Minimal scope | ✅ | ❌ | ❌ | ❌ |
| systemd managed | ✅ | ❌ | N/A | ❌ |
| Open source | ✅ | ✅ | ❌ | ❌ |

---

## Testing

Manual verification:

```bash
# Test 1: Mount starts
onbox mount
mountpoint ~/Drive  # Should return 0

# Test 2: Upload works
echo "test" > /tmp/test.txt
onbox push /tmp/test.txt

# Test 3: File visible on Drive
rclone ls drive: | grep test.txt

# Test 4: Terminal close doesn't kill mount
onbox push /tmp/test2.txt
# Close terminal window
# Open new terminal
mountpoint ~/Drive  # Still mounted!

# Test 5: Auto-unmount works
onbox push /tmp/test3.txt
sleep 301  # Wait 5 min + 1 sec
mountpoint ~/Drive  # Should fail (unmounted)
```

---

## Debugging

Enable verbose logging:

```bash
# Watch systemd logs in real-time
systemctl --user -f -u onbox-mount.service

# Or save to file
journalctl --user -u onbox-mount.service > /tmp/onbox.log

# Verbose rclone (edit service file)
ExecStart=/usr/bin/rclone mount drive: %h/Drive -v
```

---

## Questions?

See [README.md](../README.md) for usage or [GitHub Issues](/) for bugs.
