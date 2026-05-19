"""
Restore RetroArch configs to Rocknix devices from _device_configs\.
Run after a Rocknix upgrade to re-apply all settings and core overrides.

Usage:
    python Restore-DeviceConfigs.py              # restore both devices
    python Restore-DeviceConfigs.py RG35XX-SP    # restore one device
"""
import paramiko, os, sys

# Fill in the LAN IPs of your Rocknix devices.
HOSTS = {
    "RG35XX-SP": "<RG35XX-SP-IP>",
    "RG-DS":     "<RG-DS-IP>",
}
USER = "root"
PASS = "rocknix"  # default Rocknix SSH password; change if you've set a custom one

# After restore, retroarch.cfg is written as-is from backup.
# The shader paths inside core overrides reference /tmp/shaders/handheld/
# which Rocknix repopulates at every boot from the system image - no shader
# files need to be restored.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BACKUP_ROOT = os.path.join(SCRIPT_DIR, "_device_configs")

def remote_path(rel_local):
    return "/storage/.config/retroarch/" + rel_local.replace(os.sep, "/")

def get_files(device_dir):
    for root, _, files in os.walk(device_dir):
        for f in files:
            yield os.path.join(root, f)

target_devices = sys.argv[1:] if len(sys.argv) > 1 else list(HOSTS.keys())
unknown = [d for d in target_devices if d not in HOSTS]
if unknown:
    print(f"Unknown device(s): {unknown}. Valid: {list(HOSTS.keys())}")
    sys.exit(1)

errors = []

for name in target_devices:
    host = HOSTS[name]
    device_dir = os.path.join(BACKUP_ROOT, name)
    if not os.path.isdir(device_dir):
        print(f"\n[{name}] No backup found at {device_dir}, skipping.")
        continue

    print(f"\n[{name}] {host}")
    try:
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, username=USER, password=PASS, timeout=5)
        sftp = c.open_sftp()

        for local in get_files(device_dir):
            rel = os.path.relpath(local, device_dir)
            remote = remote_path(rel)
            remote_dir = remote.rsplit("/", 1)[0]

            # Ensure remote directory exists
            _, stdout, _ = c.exec_command(f"mkdir -p '{remote_dir}'")
            stdout.read()

            sftp.put(local, remote)
            print(f"  restored: {remote}")

        sftp.close()
        c.close()
        print(f"  done.")
    except Exception as e:
        msg = f"ERROR on {name} ({host}): {e}"
        print(f"  {msg}")
        errors.append(msg)

print()
if errors:
    print("Completed with errors:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
else:
    print("Restore complete.")
    print("Tip: reboot devices for all settings to take effect.")
