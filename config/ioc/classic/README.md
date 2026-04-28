# ecmc classic IOC skeleton

This IOC skeleton is for the EPICS classic controller install in `ecmc_debian`.
It does not use the EPICS `require` module.

Default hardware example:

- `EK1100` at EtherCAT slave position `0`
- `EL7041-0052` at EtherCAT slave position `1`
- one open-loop motor axis loaded from `cfg/el7041_open_loop.yaml`

Start it with:

```sh
cd /opt/epics/iocs/ecmc-classic
./st.cmd
```

Override slave positions or IOC name at startup:

```sh
IOC=ECMC_TEST EK1100_SLAVE_ID=0 EL7041_SLAVE_ID=1 ./st.cmd
```

Edit `machine.cmd` for the local EtherCAT chain.
