# Transfer files with SCP

Once the Windows workstation is running, you can copy files or folders straight into it over SSH with `scp`
(installers, game files, assets, large directories). No network share or cloud storage is involved.

This is not a feature of RTX on Demand: it is plain OpenSSH, running inside the Windows guest, which this page
documents because it is convenient with this setup.

SSH/SCP is independent of Moonlight. Moonlight gives you the display and input of the workstation; SCP moves files
directly between your machine and the guest. Neither needs the other.

## Requirements

- Windows is **running** (`~/windows-status.sh` shows `State: WINDOWS`).
- OpenSSH Server is installed and running in the Windows guest (next section).
- The SSH port of the guest is reachable from the client, on your LAN or a VPN you trust.
- The client has `ssh` and `scp` (Linux, macOS and current Windows have them).

## Enable OpenSSH Server in Windows

In an **elevated PowerShell** inside the guest (Moonlight, RDP or the noVNC console):

```powershell
# Is it installed?
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

# Install it if State is NotPresent
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start it now and at every boot
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Verify
Get-Service sshd
```

`Get-Service sshd` should report `Running`.

The installer normally creates a Windows Firewall rule named `OpenSSH-Server-In-TCP` for port 22. Check it, and
only if it is missing add a minimal one. Do not turn the firewall off.

```powershell
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue

New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
  -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
```

Restrict the rule further (`-RemoteAddress`) to your LAN if your network layout allows it. Which source address the
guest sees depends on how the VM is networked, so check that the restriction still lets you in.

## The SSH port

Inside the guest, `sshd` listens on port 22. The port you connect to **depends on how the VM is published**: with a
port mapping, as in [examples/docker-compose.yml](../examples/docker-compose.yml) (host port mapped to guest port 22),
it is the host-side port of that mapping. Use whatever your configuration publishes; the examples below call it
`SSH_PORT`. See [windows-vm.md](windows-vm.md) and [security.md](security.md).

## Test the connection

```bash
ssh -p SSH_PORT WINDOWS_USER@WINDOWS_IP
```

`WINDOWS_IP` is the address the client uses to reach the Windows guest (or the host address its SSH port is
published on), `WINDOWS_USER` is a Windows account. On first connection, check that the fingerprint is the expected
one before accepting it. If the port is 22, `-p SSH_PORT` can be omitted.

## Copy with SCP

A file to the Desktop:

```bash
scp -P SSH_PORT my-file.zip WINDOWS_USER@WINDOWS_IP:"C:/Users/WINDOWS_USER/Desktop/"
```

A directory (recursive):

```bash
scp -P SSH_PORT -r my-folder WINDOWS_USER@WINDOWS_IP:"C:/Users/WINDOWS_USER/Desktop/"
```

Notes:

- `scp` takes the port with an **uppercase `-P`** (`ssh` uses lowercase `-p`). With port 22, omit it.
- `-r` copies a directory and its contents.
- Use forward slashes and quote the remote path. It must match the real profile folder of the Windows account.
- To copy back from Windows, swap source and destination.

## After reinstalling or recreating Windows

If the guest was reinstalled or recreated, SSH may refuse with:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

This is expected: a new Windows install generates a new SSH host key, so the machine at that address and port no
longer matches the key your client stored earlier. SSH is protecting you from an impostor, and it cannot tell that
this one is legitimate.

**First confirm that the change is expected** (you did reinstall or recreate the VM, and nobody else can intercept
traffic between you and it). Do not delete host keys blindly. Then remove the stale entry:

```bash
# non-standard port
ssh-keygen -R "[WINDOWS_IP]:SSH_PORT"

# port 22
ssh-keygen -R WINDOWS_IP
```

On the next connection, verify the new fingerprint (for example by comparing it with the one shown by
`ssh-keygen -lf` on the guest's host key under `C:\ProgramData\ssh\`) and accept it.

## Security

- Prefer SSH keys to passwords. Once a key works, consider disabling password authentication in `sshd_config`.
  For an administrator account, Windows reads authorized keys from `C:\ProgramData\ssh\administrators_authorized_keys`.
- Keep SSH on your LAN or behind a VPN you trust. Never forward it from your router or expose it to the internet.
- Verify a new host key before accepting it. Do not use `StrictHostKeyChecking=no` as a habit.
- Never use an account with an empty password.

More in [security.md](security.md).
