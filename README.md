# vps-first-steps

A small, readable script for the first hour on a fresh **Ubuntu or Debian VPS**: security updates, a firewall,
fail2ban and safer SSH, without locking yourself out.

```bash
curl -fsSLO https://raw.githubusercontent.com/phantomvps/vps-first-steps/main/vps-first-steps.sh
less vps-first-steps.sh            # read it first: it is short
sudo bash vps-first-steps.sh --user deploy --allow 80,443
```

## What it does

| Step | Details | Skip with |
|---|---|---|
| Updates | `apt upgrade` now, then automatic security updates (`unattended-upgrades`) | `--no-updates` |
| Sudo user | creates the user from `--user`, adds it to `sudo`, copies root's SSH keys to it | (leave out `--user`) |
| Firewall | `ufw`: deny incoming, allow outgoing, rate-limited SSH, plus the ports in `--allow` | `--no-firewall` |
| fail2ban | bans an IP for 1 h after 5 failed SSH logins | `--no-fail2ban` |
| SSH | turns off password login **only if an SSH key is already installed** for the account you will use | `--keep-passwords` |

It detects your SSH port from `sshd -T` (or use `--ssh-port`), checks the sshd config with `sshd -t` before
reloading, and reverts its own change if the test fails. Every push is tested on Ubuntu 22.04 and 24.04 (GitHub Actions).

**Before you log out:** open a second terminal and test a new SSH login.

## Options

```
--user NAME        create / use a sudo user and copy root's SSH keys to it
--allow 80,443     extra ports to open (tcp by default, e.g. 51820/udp)
--ssh-port N       SSH port if it cannot be detected
--no-updates       skip apt upgrade and automatic updates
--no-firewall      skip ufw
--no-fail2ban      skip fail2ban
--keep-passwords   do not turn off SSH password login
--yes              do not ask for confirmation
```

## Need a server?

This script is maintained by the team behind [PhantomVPS](https://phantomvps.com?ref=github): VPS and dedicated servers with
root access, no ID documents needed, paid with Monero, Bitcoin, Litecoin, USDT, USDC, SOL or TRX.

## License

MIT
