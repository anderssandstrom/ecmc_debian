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
ECMCCFG_SRC="${ECMCCFG_SRC:-${SRC_ROOT}/ecmccfg}"
ECMCCOMP_SRC="${ECMCCOMP_SRC:-${SRC_ROOT}/ecmccomp}"
RUCKIG_SRC="${RUCKIG_SRC:-${SRC_ROOT}/ecmc_ruckig}"
ECMC_USER="${ECMC_USER:-${SUDO_USER:-}}"
read -r -a etherlab_install_args <<< "${ECMC_ETHERLAB_ARGS:-}"

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
  iproute2 \
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

install_flat_runtime_module() {
  local src="$1"
  local dest="$2"
  local file=""
  local base=""
  local mode=""

  rm -rf "${dest}"
  install -d "${dest}" "${dest}/db" "${dest}/dbd"

  while IFS= read -r file; do
    base="$(basename "${file}")"
    if [[ -e "${dest}/${base}" ]]; then
      echo "Duplicate runtime file while flattening ${src}: ${base}" >&2
      exit 1
    fi
    mode="0644"
    case "${file}" in
      *.sh|*.py)
        mode="0755"
        ;;
    esac
    install -m "${mode}" "${file}" "${dest}/${base}"
  done < <(
    find "${src}" \
      -path "${src}/.git" -prune -o \
      -path "${src}/examples" -prune -o \
      -path "${src}/tests" -prune -o \
      -path "${src}/hugo" -prune -o \
      -path "${src}/doc" -prune -o \
      -path "${src}/documentation" -prune -o \
      -path "${src}/qt" -prune -o \
      -type f \( \
        -name '*.cmd' -o \
        -name '*.script' -o \
        -name '*.sh' -o \
        -name '*.py' -o \
        -name '*.plc' -o \
        -name '*.plc_inc' -o \
        -name '*.yaml' -o \
        -name '*.yml' -o \
        -name '*.jinja2' \
      \) -print | sort
  )

  while IFS= read -r file; do
    base="$(basename "${file}")"
    if [[ -e "${dest}/db/${base}" ]]; then
      echo "Duplicate database file while flattening ${src}: ${base}" >&2
      exit 1
    fi
    install -m 0644 "${file}" "${dest}/db/${base}"
  done < <(
    find "${src}" \
      -path "${src}/.git" -prune -o \
      -path "${src}/examples" -prune -o \
      -path "${src}/tests" -prune -o \
      -path "${src}/hugo" -prune -o \
      -path "${src}/doc" -prune -o \
      -path "${src}/documentation" -prune -o \
      -path "${src}/qt" -prune -o \
      -type f \( \
        -name '*.db' -o \
        -name '*.template' -o \
        -name '*.substitutions' -o \
        -name '*.subs' \
      \) -print | sort
  )

  while IFS= read -r file; do
    base="$(basename "${file}")"
    if [[ -e "${dest}/dbd/${base}" ]]; then
      echo "Duplicate dbd file while flattening ${src}: ${base}" >&2
      exit 1
    fi
    install -m 0644 "${file}" "${dest}/dbd/${base}"
  done < <(
    find "${src}" \
      -path "${src}/.git" -prune -o \
      -path "${src}/examples" -prune -o \
      -path "${src}/tests" -prune -o \
      -path "${src}/hugo" -prune -o \
      -path "${src}/doc" -prune -o \
      -path "${src}/documentation" -prune -o \
      -path "${src}/qt" -prune -o \
      -type f -name '*.dbd' -print | sort
  )
}

install_ethercat_config_link() {
  local link_path="$1"
  local target_path="$2"

  install -d "$(dirname "${link_path}")"
  if [[ -L "${link_path}" ]]; then
    ln -sfn "${target_path}" "${link_path}"
  elif [[ -e "${link_path}" ]]; then
    if cmp -s "${link_path}" "${target_path}"; then
      rm -f "${link_path}"
      ln -s "${target_path}" "${link_path}"
    else
      echo "Keeping existing ${link_path}; active config for this installer is ${target_path}" >&2
    fi
  else
    ln -s "${target_path}" "${link_path}"
  fi
}

ensure_ethercat_device_modules() {
  local config="$1"
  local modules="$2"

  if grep -q '^DEVICE_MODULES=' "${config}"; then
    if grep -q '^DEVICE_MODULES=""' "${config}"; then
      sed -i "s/^DEVICE_MODULES=.*/DEVICE_MODULES=\"${modules}\"/" "${config}"
    fi
  else
    printf 'DEVICE_MODULES="%s"\n' "${modules}" >> "${config}"
  fi
}

link_epics_base_tools() {
  local epics_bin="${EPICS_BASE}/bin/linux-x86_64"

  if [[ ! -d "${epics_bin}" ]]; then
    echo "EPICS Base binary directory not found: ${epics_bin}" >&2
    return 0
  fi

  install -d /usr/local/bin
  for tool in \
    caget \
    cainfo \
    camonitor \
    caput \
    caRepeater \
    softIoc \
    softIocPVA \
    dbpf \
    dbgf \
    dbpr \
    dbtr \
    iocsh; do
    if [[ -x "${epics_bin}/${tool}" ]]; then
      ln -sfn "${epics_bin}/${tool}" "/usr/local/bin/${tool}"
    fi
  done
}

if [[ ! -d "${EPICS_BASE}/configure" ]]; then
  curl -fsSL "https://epics.anl.gov/download/base/base-${EPICS_BASE_VERSION}.tar.gz" \
    | tar -xz -C "${SRC_ROOT}"
  mv "${SRC_ROOT}/base-${EPICS_BASE_VERSION}" "${EPICS_BASE}"
fi
make -C "${EPICS_BASE}" -j"$(nproc)"
link_epics_base_tools

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

clone_ref "${RUCKIG_REPO}" "${RUCKIG_REF}" "${RUCKIG_SRC}"
rm -rf "${SUPPORT}/ruckig"
install -d "${SUPPORT}/ruckig"
cp -a "${RUCKIG_SRC}/ruckig/include" "${SUPPORT}/ruckig/include"
cmake -S "${RUCKIG_SRC}/ruckig" -B "${SUPPORT}/ruckig/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_PYTHON_MODULE=OFF
cmake --build "${SUPPORT}/ruckig/build" --target ruckig --parallel "$(nproc)"

"${script_dir}/install-etherlab.sh" "${etherlab_install_args[@]}"

install -d "${ETHERLAB}/etc/sysconfig"
if [[ ! -f "${ETHERLAB}/etc/sysconfig/ethercat" ]]; then
  install -m 0644 "${project_root}/config/ethercat.sysconfig.template" \
    "${ETHERLAB}/etc/sysconfig/ethercat"
fi
ensure_ethercat_device_modules "${ETHERLAB}/etc/sysconfig/ethercat" "generic"
install -d /etc/sysconfig
install_ethercat_config_link /etc/sysconfig/ethercat "${ETHERLAB}/etc/sysconfig/ethercat"
install_ethercat_config_link /etc/default/ethercat "${ETHERLAB}/etc/sysconfig/ethercat"
if [[ -f /etc/sysconfig/ethercat ]]; then
  ensure_ethercat_device_modules /etc/sysconfig/ethercat "generic"
fi

groupadd --system --force ecmc
if [[ -n "${ECMC_USER}" && "${ECMC_USER}" != "root" ]] && id "${ECMC_USER}" >/dev/null 2>&1; then
  usermod -a -G ecmc "${ECMC_USER}"
fi
install -d /etc/security/limits.d
install -m 0644 "${project_root}/config/limits.d/ecmc.conf" \
  /etc/security/limits.d/ecmc.conf

install -d /etc/systemd/system
install -m 0644 "${project_root}/config/systemd/ethercat.service" \
  /etc/systemd/system/ethercat.service
install -d /usr/local/sbin /usr/local/bin
install -m 0755 "${project_root}/config/bin/ecmc-ethercat-ifup" \
  /usr/local/sbin/ecmc-ethercat-ifup
install -m 0755 "${project_root}/config/bin/ecmc-ethercat-modules" \
  /usr/local/sbin/ecmc-ethercat-modules
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

clone_ref "${ECMCCFG_REPO}" "${ECMCCFG_REF}" "${ECMCCFG_SRC}"
install_flat_runtime_module "${ECMCCFG_SRC}" "${SUPPORT}/ecmccfg"

clone_ref "${ECMC_REPO}" "${ECMC_REF}" "${SUPPORT}/ecmc"
git -C "${SUPPORT}/ecmc" submodule update --init exprtkSupport
if [[ ! -f "${SUPPORT}/ecmc/exprtkSupport/Makefile" ]]; then
  clone_ref "${EXPRTK_REPO}" "${EXPRTK_REF}" "${SUPPORT}/ecmc/exprtkSupport"
fi
write_release "${SUPPORT}/ecmc/configure/RELEASE.local"
write_release "${SUPPORT}/ecmc/ecmcExampleTop/configure/RELEASE.local"
make -C "${SUPPORT}/ecmc" -j"$(nproc)"

clone_ref "${ECMCCOMP_REPO}" "${ECMCCOMP_REF}" "${ECMCCOMP_SRC}"
if [[ -d "${ECMCCOMP_SRC}/configure" ]]; then
  cat > "${ECMCCOMP_SRC}/configure/RELEASE.local" <<EOF_ECMCCOMP
SUPPORT=${SUPPORT}
EPICS_BASE=${EPICS_BASE}
ASYN=${SUPPORT}/asyn
MOTOR=${SUPPORT}/motor
ECMC=${SUPPORT}/ecmc
ECMCCFG=${SUPPORT}/ecmccfg
ETHERLAB=${ETHERLAB}
EOF_ECMCCOMP
fi
if [[ -f "${ECMCCOMP_SRC}/Makefile" ]]; then
  make -C "${ECMCCOMP_SRC}" -j"$(nproc)"
fi
install_flat_runtime_module "${ECMCCOMP_SRC}" "${SUPPORT}/ecmccomp"
"${script_dir}/install-classic-ioc.sh"
ldconfig

cat <<EOF_DONE

ecmc controller build complete.

Next:
  1. Edit ${ETHERLAB}/etc/sysconfig/ethercat and set MASTER0_DEVICE.
  2. Add controller users to the ecmc group and re-login.
  3. Enable and start EtherLab:
     systemctl enable --now ethercat
  4. Verify modules:
     /usr/sbin/modprobe ec_master
     /usr/sbin/modprobe ec_generic
     /usr/local/sbin/ecmc-ethercat-devices
     lsmod | grep '^ec_'
     ls -l /dev/EtherCAT*
  5. Check the master:
     ethercat master
  6. Run the ecmc example IOC from:
     /opt/epics/iocs/ecmc-classic

EOF_DONE
