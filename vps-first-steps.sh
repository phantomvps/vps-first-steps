#!/usr/bin/env bash
# vps-first-steps.sh - safe first-hour setup for a fresh Ubuntu / Debian VPS.
#
# What it does (each step can be skipped with a flag, see --help):
#   1. Installs pending security updates and turns on automatic security updates.
#   2. Creates a sudo user (optional) and copies root's authorized_keys to it.
#   3. Firewall (ufw): allows only SSH (+ ports you pass with --allow), denies the rest.
#   4. fail2ban for SSH.
#   5. SSH hardening: disables password login ONLY if a key is already installed
#      for the account you will use, so you cannot lock yourself out.
#
# Usage:  sudo bash vps-first-steps.sh [--user NAME] [--allow 80,443] [--ssh-port 22]
#                                      [--no-updates] [--no-firewall] [--no-fail2ban]
#                                      [--keep-passwords] [--yes]
# Tested on Ubuntu 22.04 and 24.04 (see .github/workflows/test.yml); written for Debian 12 / 13 too.
# License: MIT. Maintained by the PhantomVPS team - https://phantomvps.com
set -euo pipefail

USER_NAME=""; ALLOW=""; SSH_PORT=""; DO_UPDATES=1; DO_FW=1; DO_F2B=1; KEEP_PW=0; ASSUME_YES=0

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --user) USER_NAME="${2:-}"; shift 2 ;;
    --allow) ALLOW="${2:-}"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
    --no-updates) DO_UPDATES=0; shift ;;
    --no-firewall) DO_FW=0; shift ;;
    --no-fail2ban) DO_F2B=0; shift ;;
    --keep-passwords) KEEP_PW=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "run as root (sudo bash $0)"
[ -r /etc/os-release ] || die "cannot read /etc/os-release"
. /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "only Ubuntu and Debian are supported (found: ${ID:-unknown})" ;; esac

if [ -z "$SSH_PORT" ]; then
  SSH_PORT="$( { sshd -T 2>/dev/null || true; } | awk '/^port /{print $2; exit}' || true)"; SSH_PORT="${SSH_PORT:-22}"
fi
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] || die "bad --ssh-port: $SSH_PORT"
if [ -n "$USER_NAME" ]; then
  [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "bad --user name: $USER_NAME"
fi
if [ -n "$ALLOW" ]; then
  IFS=',' read -r -a PORTS <<< "$ALLOW"
  for p in "${PORTS[@]}"; do [[ "$p" =~ ^[0-9]+(/(tcp|udp))?$ ]] || die "bad port in --allow: $p"; done
else
  PORTS=()
fi

echo "Plan: updates=$DO_UPDATES firewall=$DO_FW (ssh $SSH_PORT${ALLOW:+, $ALLOW}) fail2ban=$DO_F2B user=${USER_NAME:-none} disable-passwords=$((1-KEEP_PW))"
if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Continue? [y/N] " a; case "$a" in y|Y|yes) ;; *) echo "Aborted."; exit 1 ;; esac
fi

export DEBIAN_FRONTEND=noninteractive

if [ "$DO_UPDATES" -eq 1 ]; then
  info "Installing updates"
  apt-get update -q
  apt-get -y -q upgrade
  apt-get -y -q install unattended-upgrades
  printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades
fi

if [ -n "$USER_NAME" ]; then
  if id "$USER_NAME" >/dev/null 2>&1; then
    info "User $USER_NAME exists"
  else
    info "Creating user $USER_NAME (set a password for sudo afterwards: passwd $USER_NAME)"
    adduser --disabled-password --gecos "" "$USER_NAME"
  fi
  usermod -aG sudo "$USER_NAME"
  if [ -s /root/.ssh/authorized_keys ]; then
    home="$(getent passwd "$USER_NAME" | cut -d: -f6)"
    install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$home/.ssh"
    install -m 600 -o "$USER_NAME" -g "$USER_NAME" /root/.ssh/authorized_keys "$home/.ssh/authorized_keys"
    info "Copied root's SSH keys to $USER_NAME"
  fi
fi

if [ "$DO_FW" -eq 1 ]; then
  info "Firewall (ufw)"
  apt-get -y -q install ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw limit "$SSH_PORT/tcp"
  for p in "${PORTS[@]}"; do ufw allow "$p"; done
  ufw --force enable
fi

if [ "$DO_F2B" -eq 1 ]; then
  info "fail2ban for SSH"
  apt-get -y -q install fail2ban
  printf '[sshd]\nenabled = true\nport = %s\nmaxretry = 5\nbantime = 1h\n' "$SSH_PORT" > /etc/fail2ban/jail.d/sshd-local.conf
  systemctl enable --now fail2ban
  systemctl restart fail2ban
fi

if [ "$KEEP_PW" -eq 0 ]; then
  target="${USER_NAME:-root}"
  home="$(getent passwd "$target" | cut -d: -f6)"
  if [ -s "$home/.ssh/authorized_keys" ]; then
    info "Disabling SSH password login (a key is installed for $target)"
    install -d /etc/ssh/sshd_config.d
    printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin prohibit-password\n' > /etc/ssh/sshd_config.d/10-first-steps.conf
    install -d -m 755 /run/sshd   # Ubuntu 24.04+ starts sshd on demand (ssh.socket); sshd -t needs this directory
    sshd -t || { rm -f /etc/ssh/sshd_config.d/10-first-steps.conf; die "sshd config test failed, change reverted"; }
    if systemctl is-active --quiet ssh || systemctl is-active --quiet sshd; then
      systemctl reload ssh 2>/dev/null || systemctl reload sshd
    else
      info "sshd starts on demand here: the new settings apply to the next SSH login"
    fi
  else
    info "No SSH key found for $target: password login stays ON (add a key, then run again)"
  fi
fi

info "Done. Keep this session open and test a NEW SSH login before you log out."
