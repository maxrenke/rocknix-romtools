"""
Pull RetroArch configs from Rocknix devices into _device_configs/.
Run this before Backup-RocknixBackup.ps1, or it will be called automatically by it.
"""
import paramiko, os, sys

# Fill in the LAN IPs of your Rocknix devices.
HOSTS = {
    "RG35XX-SP": "<RG35XX-SP-IP>",
    "RG-DS":     "<RG-DS-IP>",
}
USER = "root"
PASS = "rocknix"  # default Rocknix SSH password; change if you've set a custom one

REMOTE_FILES = [
    "/storage/.config/retroarch/retroarch.cfg",
    "/storage/.config/retroarch/config/mGBA/mGBA.cfg",
    "/storage/.config/retroarch/config/Gambatte/Gambatte.cfg",
    "/storage/.config/retroarch/config/DeSmuME/DeSmuME.cfg",
]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
BACKUP_ROOT = os.path.join(SCRIPT_DIR, "_device_configs")

def local_path(device_name, remote):
    # Strip /storage/.config/retroarch/ prefix -> store flat under device dir
    rel = remote.replace("/storage/.config/retroarch/", "")
    return os.path.join(BACKUP_ROOT, device_name, rel.replace("/", os.sep))

errors = []

for name, host in HOSTS.items():
    print(f"\n[{name}] {host}")
    try:
        c = paramiko.SSHClient()
        c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        c.connect(host, username=USER, password=PASS, timeout=5)
        sftp = c.open_sftp()

        for remote in REMOTE_FILES:
            dest = local_path(name, remote)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            try:
                sftp.get(remote, dest)
                print(f"  pulled: {remote}")
            except FileNotFoundError:
                print(f"  skip (not found): {remote}")

        sftp.close()
        c.close()
    except Exception as e:
        msg = f"ERROR connecting to {name} ({host}): {e}"
        print(f"  {msg}")
        errors.append(msg)

print()
if errors:
    print("Completed with errors:")
    for e in errors:
        print(f"  {e}")
    sys.exit(1)
else:
    print("All configs synced successfully.")
