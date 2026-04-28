# ecmc controller environment.

export EPICS_ROOT=/opt/epics
export EPICS_BASE=/opt/epics/base
export SUPPORT=/opt/epics/support
export ETHERLAB=/opt/etherlab

case ":${PATH}:" in
  *:/opt/etherlab/bin:*) ;;
  *) PATH="/opt/etherlab/bin:${PATH}" ;;
esac

case ":${PATH}:" in
  *:/opt/epics/base/bin/linux-x86_64:*) ;;
  *) PATH="/opt/epics/base/bin/linux-x86_64:${PATH}" ;;
esac

case ":${LD_LIBRARY_PATH:-}:" in
  *:/opt/etherlab/lib:*) ;;
  *) LD_LIBRARY_PATH="/opt/etherlab/lib:${LD_LIBRARY_PATH:-}" ;;
esac

case ":${LD_LIBRARY_PATH:-}:" in
  *:/opt/epics/support/ruckig/build:*) ;;
  *) LD_LIBRARY_PATH="/opt/epics/support/ruckig/build:${LD_LIBRARY_PATH:-}" ;;
esac

export PATH
export LD_LIBRARY_PATH
