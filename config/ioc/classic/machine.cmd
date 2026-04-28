# Machine-specific ecmccfg startup loaded by st.cmd.
#
# Default example:
#   slave 0: EK1100 EtherCAT coupler
#   slave 1: EL7041-0052 stepper terminal

iocshLoad "${ecmccfg_DIR}addSlave.cmd", "SLAVE_ID=${EK1100_SLAVE_ID=0},HW_DESC=EK1100"

iocshLoad "${ecmccfg_DIR}addSlave.cmd", "SLAVE_ID=${EL7041_SLAVE_ID=1},HW_DESC=EL7041-0052"
iocshLoad "${ecmccfg_DIR}applyComponent.cmd", "COMP=Motor-Generic-2Phase-Stepper,MACROS='I_MAX_MA=${I_MAX_MA=1000},I_STDBY_MA=${I_STDBY_MA=200},U_NOM_MV=${U_NOM_MV=48000},R_COIL_MOHM=${R_COIL_MOHM=1230},SPEED_RANGE=${SPEED_RANGE=2}'"
epicsEnvSet("DRV_SID", "${ECMC_EC_SLAVE_NUM}")

iocshLoad "${ecmccfg_DIR}loadYamlAxis.cmd", "FILE=./cfg/el7041_open_loop.yaml,DEV=${IOC},AX_NAME=${AX_NAME=M1},AXIS_ID=${AXIS_ID=1},DRV_SID=${DRV_SID},ENC_SID=${DRV_SID},ENC_CH=01"

ecmcEpicsEnvSetCalc("ECMC_TEMP_PERIOD_NANO_SECS", "1000/${ECMC_EC_SAMPLE_RATE=1000}*1E6")
ecmcConfigOrDie "Cfg.EcSlaveConfigDC(${DRV_SID},0x300,${ECMC_TEMP_PERIOD_NANO_SECS},0,0,0)"
