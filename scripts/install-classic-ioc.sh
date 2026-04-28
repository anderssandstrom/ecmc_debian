#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"

IOC_DIR="${IOC_DIR:-/opt/epics/iocs/ecmc-classic}"
EPICS_BASE="${EPICS_BASE:-/opt/epics/base}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root, for example: sudo $0" >&2
  exit 1
fi

if [[ ! -x /opt/epics/support/ecmc/ecmcExampleTop/bin/linux-x86_64/ecmcIoc ]]; then
  echo "Missing ecmcIoc binary. Run scripts/install-controller.sh first." >&2
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
