# ecmc Debian controller install

This project is for installing a real Debian controller that can run ecmc
against local EtherCAT hardware. It is intentionally separate from
`ecmc_docker`.

`ecmc_docker` is useful for build validation and IOC smoke testing. It builds
EtherLab without kernel modules, so it is not a controller install.

This installer is meant to run on the target Debian 13 controller and build
EtherLab kernel modules for the running kernel.

## Current scope

Phase 1 is a host bootstrap script:

```sh
sudo ./scripts/install-controller.sh
```

To rebuild only EtherLab and its kernel modules after a kernel update or
EtherCAT setup change:

```sh
sudo ./scripts/install-etherlab.sh
```

There is also a first live USB build skeleton:

```sh
sudo ./scripts/build-live-usb.sh
```

Run this on a Debian 13 build host. It uses Debian `live-build` to produce an
amd64/x86_64 ISO-hybrid image that can be written to USB.

It installs build dependencies, builds:

- EPICS Base
- asyn
- motorESS
- Ruckig
- EtherLab 1.6.3 with kernel modules
- ecmccfg
- ecmc
- ecmccomp

It also installs:

- `/etc/systemd/system/ethercat.service`
- `/etc/security/limits.d/ecmc.conf`
- `/etc/profile.d/ecmc.sh`
- `/etc/ld.so.conf.d/ecmc.conf`
- an `ecmc` user group for realtime limits

The default install prefix is:

```text
/opt/epics
/opt/etherlab
```

## Important hardware setup

After installation, edit:

```text
/opt/etherlab/etc/sysconfig/ethercat
```

Set `MASTER0_DEVICE` to the MAC address of the controller NIC connected to the
EtherCAT chain.

Then start the master:

```sh
sudo systemctl enable --now ethercat
```

## Module signing and Secure Boot

During `make modules_install`, Debian may print messages like:

```text
SSL error: ... No such file or directory ... signing_key.pem
```

This means the kernel build tried to sign the out-of-tree EtherLab modules but
the header tree does not contain a private signing key. If the install continues
to `DEPMOD`, the modules were still installed.

For normal controller tests, disable Secure Boot in firmware. If Secure Boot is
enabled, unsigned EtherLab modules may fail to load with:

```text
Key was rejected by service
```

After installation, verify module loading:

```sh
sudo /usr/sbin/modprobe ec_master
sudo /usr/sbin/modprobe ec_generic
lsmod | grep '^ec_'
```

The EtherLab command is installed at:

```sh
/opt/etherlab/bin/ethercat
```

New login shells get `/opt/etherlab/bin` and the EPICS Base binary path through
`/etc/profile.d/ecmc.sh`.

For first tests, the installer defaults to the EtherLab generic driver. Native
drivers can be added later for sites that need them.

## Next steps

The live USB currently includes the installer and Debian's live installer. The
next step is to add a fully unattended disk-install profile that runs the ecmc
controller installer in the installed target system.
