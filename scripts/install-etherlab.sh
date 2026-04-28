#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

# shellcheck source=../config/versions.env
source "${project_root}/config/versions.env"

ETHERLAB="${ETHERLAB:-/opt/etherlab}"
SRC_ROOT="${SRC_ROOT:-/opt/src/ecmc-controller}"
clean_install=0
clean_source=0

usage() {
  cat <<EOF_USAGE
Usage: sudo $0 [--clean] [--clean-source]

Options:
  --clean         Stop EtherLab, unload EtherLab modules, remove the installed
                  EtherLab prefix, generated service/helper links, and installed
                  EtherLab kernel modules for the running kernel. The active
                  ethercat sysconfig file is preserved and restored.
  --clean-source  Also remove the EtherLab source checkout before cloning.
  -h, --help      Show this help.
EOF_USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)
      clean_install=1
      ;;
    --clean-source)
      clean_source=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root, for example: sudo $0" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  autoconf \
  automake \
  build-essential \
  ca-certificates \
  flex \
  git \
  kmod \
  libtool \
  m4 \
  pkg-config \
  "linux-headers-$(uname -r)"

kernel_build_dir="/lib/modules/$(uname -r)/build"
if [[ ! -d "${kernel_build_dir}" ]]; then
  echo "Missing kernel build directory: ${kernel_build_dir}" >&2
  echo "Install matching linux-headers for the running kernel and retry." >&2
  exit 1
fi

mkdir -p "${SRC_ROOT}" "${ETHERLAB}"

clean_etherlab_install() {
  local saved_config=""
  local saved_config_dir=""

  if [[ -f /etc/sysconfig/ethercat ]]; then
    saved_config_dir="$(mktemp -d)"
    saved_config="${saved_config_dir}/ethercat"
    cp -aL /etc/sysconfig/ethercat "${saved_config}"
  elif [[ -f "${ETHERLAB}/etc/sysconfig/ethercat" ]]; then
    saved_config_dir="$(mktemp -d)"
    saved_config="${saved_config_dir}/ethercat"
    cp -aL "${ETHERLAB}/etc/sysconfig/ethercat" "${saved_config}"
  fi

  systemctl stop ethercat 2>/dev/null || true
  /usr/sbin/modprobe -r ec_generic ec_igb ec_igc ec_ccat ec_master 2>/dev/null || true

  rm -rf "${ETHERLAB}"
  rm -rf "/lib/modules/$(uname -r)/ethercat"
  rm -f /usr/local/bin/ethercat
  rm -f /usr/local/sbin/ecmc-ethercat-devices
  rm -f /etc/systemd/system/ethercat.service
  if [[ -L /etc/sysconfig/ethercat ]]; then
    rm -f /etc/sysconfig/ethercat
  fi

  mkdir -p "${ETHERLAB}" /etc/sysconfig
  if [[ -n "${saved_config}" ]]; then
    install -d "${ETHERLAB}/etc/sysconfig"
    install -m 0644 "${saved_config}" "${ETHERLAB}/etc/sysconfig/ethercat"
    rm -rf "${saved_config_dir}"
  fi

  depmod -a
  systemctl daemon-reload 2>/dev/null || true
}

if [[ "${clean_install}" -eq 1 ]]; then
  clean_etherlab_install
fi

if [[ "${clean_source}" -eq 1 ]]; then
  rm -rf "${SRC_ROOT}/ethercat"
fi

clone_ref() {
  local repo="$1"
  local ref="$2"
  local dest="$3"

  if [[ -d "${dest}/.git" ]]; then
    git -C "${dest}" fetch --depth 1 origin "${ref}"
    git -C "${dest}" checkout --detach FETCH_HEAD
  else
    git clone --depth 1 --branch "${ref}" "${repo}" "${dest}"
  fi
}

clone_ref "${ETHERLAB_REPO}" "${ETHERLAB_REF}" "${SRC_ROOT}/ethercat"
(
  cd "${SRC_ROOT}/ethercat"
  ./bootstrap
  ./configure \
    --prefix="${ETHERLAB}" \
    --with-linux-dir="${kernel_build_dir}" \
    --enable-generic \
    --enable-igb \
    --enable-igc \
    --enable-ccat \
    --enable-tool \
    --enable-userlib \
    --disable-8139too \
    --disable-e100 \
    --disable-e1000 \
    --disable-e1000e \
    --disable-r8169
  make -j"$(nproc)"
  make modules
  make install
  make modules_install
)
depmod -a

if command -v mokutil >/dev/null 2>&1; then
  if mokutil --sb-state 2>/dev/null | grep -qi 'enabled'; then
    cat >&2 <<EOF_SECUREBOOT

WARNING: Secure Boot appears to be enabled.

EtherLab modules built by this installer are not signed with a Machine Owner
Key. They may install successfully but fail to load with "Key was rejected by
service". Disable Secure Boot in firmware or add a module-signing/MOK step.

EOF_SECUREBOOT
  fi
fi

install -d "${ETHERLAB}/etc/sysconfig"
if [[ ! -f "${ETHERLAB}/etc/sysconfig/ethercat" ]]; then
  install -m 0644 "${project_root}/config/ethercat.sysconfig.template" \
    "${ETHERLAB}/etc/sysconfig/ethercat"
fi
install -d /etc/sysconfig
if [[ ! -e /etc/sysconfig/ethercat ]]; then
  ln -s "${ETHERLAB}/etc/sysconfig/ethercat" /etc/sysconfig/ethercat
fi

install -d /etc/systemd/system
install -m 0644 "${project_root}/config/systemd/ethercat.service" \
  /etc/systemd/system/ethercat.service
install -d /usr/local/sbin /usr/local/bin
install -m 0755 "${project_root}/config/bin/ecmc-ethercat-devices" \
  /usr/local/sbin/ecmc-ethercat-devices
ln -sfn "${ETHERLAB}/bin/ethercat" /usr/local/bin/ethercat
systemctl daemon-reload || true

install -d /etc/profile.d /etc/ld.so.conf.d
install -m 0644 "${project_root}/config/profile.d/ecmc.sh" \
  /etc/profile.d/ecmc.sh
install -m 0644 "${project_root}/config/ld.so.conf.d/ecmc.conf" \
  /etc/ld.so.conf.d/ecmc.conf
ldconfig
for profile in /etc/bash.bashrc /etc/zsh/zshrc; do
  if [[ -f "${profile}" ]] && ! grep -q '/etc/profile.d/ecmc.sh' "${profile}"; then
    cat >> "${profile}" <<'EOF_PROFILE'

if [ -r /etc/profile.d/ecmc.sh ]; then
  . /etc/profile.d/ecmc.sh
fi
EOF_PROFILE
  fi
done

cat <<EOF_DONE

EtherLab install complete.

Next:
  1. Edit ${ETHERLAB}/etc/sysconfig/ethercat and set MASTER0_DEVICE.
  2. Verify modules:
     /usr/sbin/modprobe ec_master
     /usr/sbin/modprobe ec_generic
     /usr/local/sbin/ecmc-ethercat-devices
     lsmod | grep '^ec_'
     ls -l /dev/EtherCAT*
  3. Enable and start EtherLab:
     systemctl enable --now ethercat
  4. Check the master:
     ethercat master

EOF_DONE
