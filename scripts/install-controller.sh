#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

# shellcheck source=../config/versions.env
source "${project_root}/config/versions.env"

EPICS_ROOT="${EPICS_ROOT:-/opt/epics}"
EPICS_BASE="${EPICS_BASE:-${EPICS_ROOT}/base}"
SUPPORT="${SUPPORT:-${EPICS_ROOT}/support}"
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
  bison \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  flex \
  git \
  kmod \
  libreadline-dev \
  libtirpc-dev \
  libtool \
  m4 \
  perl \
  pkg-config \
  python3 \
  re2c \
  "linux-headers-$(uname -r)"

kernel_build_dir="/lib/modules/$(uname -r)/build"
if [[ ! -d "${kernel_build_dir}" ]]; then
  echo "Missing kernel build directory: ${kernel_build_dir}" >&2
  echo "Install matching linux-headers for the running kernel and retry." >&2
  exit 1
fi

mkdir -p "${EPICS_ROOT}" "${SUPPORT}" "${SRC_ROOT}" "${ETHERLAB}"

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

write_release() {
  local dest="$1"

  cat > "${dest}" <<EOF_RELEASE
SUPPORT=${SUPPORT}
EPICS_BASE=${EPICS_BASE}
ASYN=${SUPPORT}/asyn
MOTOR=${SUPPORT}/motor
EXPRTK=${SUPPORT}/ecmc/exprtkSupport
RUCKIG=${SUPPORT}/ruckig
ETHERLAB=${ETHERLAB}
ECMCCFG=${SUPPORT}/ecmccfg
ECMCCOMP=${SUPPORT}/ecmccomp
EOF_RELEASE
}

if [[ ! -d "${EPICS_BASE}/configure" ]]; then
  curl -fsSL "https://epics.anl.gov/download/base/base-${EPICS_BASE_VERSION}.tar.gz" \
    | tar -xz -C "${SRC_ROOT}"
  mv "${SRC_ROOT}/base-${EPICS_BASE_VERSION}" "${EPICS_BASE}"
fi
make -C "${EPICS_BASE}" -j"$(nproc)"

clone_ref "${ASYN_REPO}" "${ASYN_REF}" "${SUPPORT}/asyn"
cat > "${SUPPORT}/asyn/configure/RELEASE.local" <<EOF_ASYN
SUPPORT=${SUPPORT}
EPICS_BASE=${EPICS_BASE}
EOF_ASYN
printf 'TIRPC=YES\n' > "${SUPPORT}/asyn/configure/CONFIG_SITE.local"
make -C "${SUPPORT}/asyn" -j"$(nproc)"

clone_ref "${MOTOR_REPO}" "${MOTOR_REF}" "${SUPPORT}/motor"
cat > "${SUPPORT}/motor/configure/RELEASE.local" <<EOF_MOTOR
SUPPORT=${SUPPORT}
EPICS_BASE=${EPICS_BASE}
ASYN=${SUPPORT}/asyn
EOF_MOTOR
make -C "${SUPPORT}/motor" -j"$(nproc)"

clone_ref "${RUCKIG_REPO}" "${RUCKIG_REF}" "${SUPPORT}/ruckig"
cmake -S "${SUPPORT}/ruckig" -B "${SUPPORT}/ruckig/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON
cmake --build "${SUPPORT}/ruckig/build" --target ruckig --parallel "$(nproc)"

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

install -d "${ETHERLAB}/etc/sysconfig"
if [[ ! -f "${ETHERLAB}/etc/sysconfig/ethercat" ]]; then
  install -m 0644 "${project_root}/config/ethercat.sysconfig.template" \
    "${ETHERLAB}/etc/sysconfig/ethercat"
fi

groupadd --system --force ecmc
install -d /etc/security/limits.d
install -m 0644 "${project_root}/config/limits.d/ecmc.conf" \
  /etc/security/limits.d/ecmc.conf

install -d /etc/systemd/system
install -m 0644 "${project_root}/config/systemd/ethercat.service" \
  /etc/systemd/system/ethercat.service
systemctl daemon-reload || true

clone_ref "${ECMCCFG_REPO}" "${ECMCCFG_REF}" "${SUPPORT}/ecmccfg"

clone_ref "${ECMC_REPO}" "${ECMC_REF}" "${SUPPORT}/ecmc"
git -C "${SUPPORT}/ecmc" submodule update --init exprtkSupport
if [[ ! -f "${SUPPORT}/ecmc/exprtkSupport/Makefile" ]]; then
  clone_ref "${EXPRTK_REPO}" "${EXPRTK_REF}" "${SUPPORT}/ecmc/exprtkSupport"
fi
write_release "${SUPPORT}/ecmc/configure/RELEASE.local"
write_release "${SUPPORT}/ecmc/ecmcExampleTop/configure/RELEASE.local"
make -C "${SUPPORT}/ecmc" -j"$(nproc)"

clone_ref "${ECMCCOMP_REPO}" "${ECMCCOMP_REF}" "${SUPPORT}/ecmccomp"
if [[ -d "${SUPPORT}/ecmccomp/configure" ]]; then
  cat > "${SUPPORT}/ecmccomp/configure/RELEASE.local" <<EOF_ECMCCOMP
SUPPORT=${SUPPORT}
EPICS_BASE=${EPICS_BASE}
ASYN=${SUPPORT}/asyn
MOTOR=${SUPPORT}/motor
ECMC=${SUPPORT}/ecmc
ECMCCFG=${SUPPORT}/ecmccfg
ETHERLAB=${ETHERLAB}
EOF_ECMCCOMP
fi
if [[ -f "${SUPPORT}/ecmccomp/Makefile" ]]; then
  make -C "${SUPPORT}/ecmccomp" -j"$(nproc)"
fi

cat <<EOF_DONE

ecmc controller build complete.

Next:
  1. Edit ${ETHERLAB}/etc/sysconfig/ethercat and set MASTER0_DEVICE.
  2. Add controller users to the ecmc group and re-login.
  3. Enable and start EtherLab:
     systemctl enable --now ethercat
  4. Run the ecmc example IOC from:
     ${SUPPORT}/ecmc/ecmcExampleTop/iocBoot/ecmcIoc

EOF_DONE
