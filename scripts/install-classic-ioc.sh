#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

IOC_DIR="${IOC_DIR:-/opt/epics/iocs/ecmc-classic}"
EPICS_BASE="${EPICS_BASE:-/opt/epics/base}"
ECMC_TOP="${ECMC_TOP:-/opt/epics/support/ecmc}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root, for example: sudo $0" >&2
  exit 1
fi

find_ecmc_ioc() {
  local binary=""

  if [[ -n "${EPICS_HOST_ARCH:-}" && -x "${ECMC_TOP}/ecmcExampleTop/bin/${EPICS_HOST_ARCH}/ecmcIoc" ]]; then
    printf '%s\n' "${ECMC_TOP}/ecmcExampleTop/bin/${EPICS_HOST_ARCH}/ecmcIoc"
    return 0
  fi

  binary="$(find "${ECMC_TOP}" -path '*/bin/*/ecmcIoc' -type f -perm -111 -print -quit 2>/dev/null || true)"
  if [[ -n "${binary}" ]]; then
    printf '%s\n' "${binary}"
    return 0
  fi

  return 1
}

ecmc_ioc="$(find_ecmc_ioc || true)"
if [[ -z "${ecmc_ioc}" ]]; then
  echo "Missing ecmcIoc binary below ${ECMC_TOP}." >&2
  echo "Run scripts/install-controller.sh first, or check the ecmc build log for the IOC build failure." >&2
  exit 1
fi
if [[ ! -f /opt/epics/support/ecmccfg/startup.cmd ]]; then
  echo "Missing flattened ecmccfg runtime install: /opt/epics/support/ecmccfg/startup.cmd" >&2
  exit 1
fi
if [[ ! -f /opt/epics/support/ecmccomp/applyComponent.cmd ]]; then
  echo "Missing flattened ecmccomp runtime install: /opt/epics/support/ecmccomp/applyComponent.cmd" >&2
  exit 1
fi

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

install -d "${IOC_DIR}"
cp -a "${project_root}/config/ioc/classic/." "${IOC_DIR}/"
sed -i "1s|^#!.*|#!${ecmc_ioc}|" "${IOC_DIR}/st.cmd"
chmod 0755 "${IOC_DIR}/st.cmd"
link_epics_base_tools

cat <<EOF_DONE

Classic ecmc IOC installed in:
  ${IOC_DIR}

Start it with:
  cd ${IOC_DIR}
  ./st.cmd

Edit machine.cmd for the local EtherCAT chain.

EOF_DONE
