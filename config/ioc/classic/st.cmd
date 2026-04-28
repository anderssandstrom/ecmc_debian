#!/opt/epics/support/ecmc/ecmcExampleTop/bin/linux-x86_64/ecmcIoc

on error halt

epicsEnvSet("IOC", "${IOC=ECMC_TEST}")
epicsEnvSet("MASTER_ID", "${MASTER_ID=0}")
epicsEnvSet("EC_RATE", "${EC_RATE=1000}")
epicsEnvSet("ENG_MODE", "${ENG_MODE=1}")
epicsEnvSet("MODE", "${MODE=FULL}")
epicsEnvSet("ECMC_VER", "${ECMC_VER=v11.0.7_RC1}")

epicsEnvSet("SUPPORT", "/opt/epics/support")
epicsEnvSet("ECMC_TOP", "${SUPPORT}/ecmc")
epicsEnvSet("ECMC_IOC_TOP", "${ECMC_TOP}/ecmcExampleTop")
epicsEnvSet("ecmccfg_DIR", "${SUPPORT}/ecmccfg/")
epicsEnvSet("ecmccfg_DB", "${SUPPORT}/ecmccfg/db")

epicsEnvSet("EPICS_DB_INCLUDE_PATH", "${ECMC_IOC_TOP}/db:${ECMC_TOP}/db:${ecmccfg_DB}:${SUPPORT}/asyn/db:${SUPPORT}/motor/db")

cd "${ECMC_IOC_TOP}"
dbLoadDatabase "dbd/ecmcIoc.dbd"
ecmcIoc_registerRecordDeviceDriver pdbbase

cd "/opt/epics/iocs/ecmc-classic"

iocshLoad "${ecmccfg_DIR}startup.cmd", "IOC=${IOC},MASTER_ID=${MASTER_ID},EC_RATE=${EC_RATE},ENG_MODE=${ENG_MODE},MODE=${MODE},ECMC_VER=${ECMC_VER},MAX_PARAM_COUNT=${MAX_PARAM_COUNT=3000},EC_TOOL_PATH=/opt/etherlab/bin/ethercat,ECMC_REQUIRE_ECMC=#-"
iocshLoad "./machine.cmd"

iocInit
