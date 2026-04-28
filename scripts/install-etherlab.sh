#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

# shellcheck source=../config/versions.env
source "${project_root}/config/versions.env"

ETHERLAB="${ETHERLAB:-/opt/etherlab}"
SRC_ROOT="${SRC_ROOT:-/opt/src/ecmc-controller}"

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

install -d /etc/systemd/system
install -m 0644 "${project_root}/config/systemd/ethercat.service" \
  /etc/systemd/system/ethercat.service
systemctl daemon-reload || true

cat <<EOF_DONE

EtherLab install complete.

Next:
  1. Edit ${ETHERLAB}/etc/sysconfig/ethercat and set MASTER0_DEVICE.
  2. Verify modules:
     modprobe ec_master
     modprobe ec_generic
     lsmod | grep '^ec_'
  3. Enable and start EtherLab:
     systemctl enable --now ethercat

EOF_DONE
