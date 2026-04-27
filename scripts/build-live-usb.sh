#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
live_root="${project_root}/live"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on a Debian 13 build host, for example:" >&2
  echo "  sudo $0" >&2
  exit 1
fi

if ! command -v lb >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends live-build live-boot live-config
fi

rm -rf "${live_root}/config/includes.chroot/usr/local/share/ecmc-debian"
mkdir -p "${live_root}/config/includes.chroot/usr/local/share/ecmc-debian"
cp -a "${project_root}/config" "${live_root}/config/includes.chroot/usr/local/share/ecmc-debian/"
cp -a "${project_root}/scripts" "${live_root}/config/includes.chroot/usr/local/share/ecmc-debian/"

(
  cd "${live_root}"
  ./auto/config
  ./auto/build
)

cat <<EOF_DONE

Live image build complete.

Look for:
  ${live_root}/ecmc-debian-13-live*.hybrid.iso

Write to a USB stick with a command like:
  sudo dd if=${live_root}/ecmc-debian-13-live-amd64.hybrid.iso of=/dev/sdX bs=4M status=progress conv=fsync

Replace /dev/sdX with the USB device, not a partition.

EOF_DONE
