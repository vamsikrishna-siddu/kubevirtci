#!/bin/bash

WITH_REGISTRY=false
NODES=1
PREFIX="kubevirt-"

COMMAND=$1
shift

if [[    "${COMMAND}" != "run" \
     && "${COMMAND}" != "provision" \
     && "${COMMAND}" != "ssh" \
     && "${COMMAND}" != "ps" \
     && "${COMMAND}" != "rm" ]]; then
        echo "No valid command provides. Valid commands  are 'run', 'provision', 'ssh' and 'rm'."
        exit 1
fi

while true; do
  case "$1" in
    -p | --prefix ) PREFIX="${2}-"; shift 2 ;;
    -n | --nodes ) NODES="$2"; shift 2 ;;
    -s | --scripts ) SCRIPTS="$2"; shift 2 ;;
    -t | --tag ) TAG="$2"; shift 2 ;;
    -b | --base ) BASE="$2"; shift 2 ;;
    --tls-port ) TLS_PORT="$2"; shift 2 ;;
    --ssh-port ) SSH_PORT="$2"; shift 2 ;;
    --vnc-port ) VNC_PORT="$2"; shift 2 ;;
    --registry-port ) REGISTRY_PORT="$2"; shift 2 ;;
    --registry-volume ) REGISTRY_VOLUME="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

if [ "$COMMAND" = "rm" ] ; then
  docker stop $(docker ps --filter="name=${PREFIX}" -q)
  docker rm $(docker ps -a --filter="name=${PREFIX}" -q)
  exit 0
fi

if [ "$COMMAND" = "ps" ] ; then
  docker ps --filter="name=${PREFIX}"
  exit 0
fi

test -t 1 && USE_TTY="-it"
if [ "$COMMAND" = "ssh" ] ; then
  docker exec ${USE_TTY} ${PREFIX}${1} ssh.sh
  exit 0
fi

PORTS=""
if [ -n "${TLS_PORT}" ]; then PORTS="${PORTS} -p ${TLS_PORT}:6443"; fi
if [ -n "${SSH_PORT}" ]; then PORTS="${PORTS} -p ${SSH_PORT}:2201"; fi
if [ -n "${VNC_PORT}" ]; then PORTS="${PORTS} -p ${VNC_PORT}:5901"; fi
if [ -n "${REGISTRY_PORT}" ]; then PORTS="${PORTS} -p ${REGISTRY_PORT}:5000"; fi

if [ -z "${BASE}" ]; then echo "Base image is not set. Use  '-b or --base' to set it."; exit 1; fi

if [ "$COMMAND" == "provision" ] ; then
  if [ -z "${TAG}" ]; then echo "Resultin build tag not set. Use  '-t or --tag' to set it."; exit 1; fi
  if [ -z "${SCRIPTS}" ]; then echo "Provision script is not set. Use  '-s or --script' to set it."; exit 1; fi
else
  if [ "$NODES" -lt "1" ]; then echo "The number of nodes must be greater or equal to 1."; exit 1 ; fi
fi

set -e

function finish() {
    set +e
    for id in ${CONTAINERS}; do
      docker stop ${id}
      docker rm ${id}
    done
    set -e
}

trap finish EXIT SIGINT SIGTERM SIGQUIT

DNSMASQ_CID=$(docker run -d ${PORTS} -e NUM_NODES=${NODES} --name ${PREFIX}dnsmasq --privileged ${BASE} /bin/bash -c /dnsmasq.sh)
CONTAINERS=${DNSMASQ_CID}

if [ "$COMMAND" == "provision" ] ; then
  VM_CID=$(docker run -d --privileged --net=container:${DNSMASQ_CID} --name ${PREFIX}node01 ${BASE} /vm.sh --provision)
  CONTAINERS="${CONTAINERS} ${VM_CID}"
  docker cp ${SCRIPTS} ${VM_CID}:/scripts
  docker exec ${VM_CID} /bin/bash -c "while [ ! -f /usr/local/bin/ssh.sh ] ; do sleep 1; done"
  docker exec ${VM_CID} /bin/bash -c "ssh.sh sudo /bin/bash < /scripts/provision.sh"
  docker exec ${VM_CID} ssh.sh "sudo shutdown -h"
  docker exec ${VM_CID} /bin/bash -c "rm /usr/local/bin/ssh.sh"
  docker wait ${VM_CID}
  docker commit --change "ENV PROVISIONED TRUE" ${VM_CID} ${TAG}
else
  # Start registry
  if [ -n "$REGISTRY_VOLUME" ]; then
    if [ -z "$(docker volume list | grep ${REGISTRY_VOLUME})" ]; then
      docker volume create --name ${REGISTRY_VOLUME}
    fi
    REGISTRY_VOLUME="-v ${REGISTRY_VOLUME}:/var/lib/registry"
  fi
  REGISTRY_CID=$(docker run -d --net=container:${DNSMASQ_CID} --name ${PREFIX}registry ${REGISTRY_VOLUME} registry:2)
  CONTAINERS="${CONTAINERS} ${REGISTRY_CID}"

  # Let dnsmasq learn the registry dns name
  docker exec ${DNSMASQ_CID} /bin/bash -c 'echo 192.168.66.2 registry > /etc/hosts && kill -1 1'

  # Start VMs      
  for i in $(seq 1 ${NODES}); do
    NODE_NUM="$(printf "%02d" ${i})"
    VM_CID=$(docker run -d --privileged -e NODE_NUM=${NODE_NUM} --net=container:${DNSMASQ_CID} --name ${PREFIX}node${NODE_NUM} ${BASE} /bin/bash -c /vm.sh)
    CONTAINERS="${CONTAINERS} ${VM_CID}"
    docker exec ${VM_CID} /bin/bash -c "while [ ! -f /usr/local/bin/ssh.sh ] ; do sleep 1; done"
    if docker exec ${VM_CID} /bin/bash -c "test -f /scripts/node${NODE_NUM}.sh" ; then
      docker exec ${VM_CID} /bin/bash -c "ssh.sh sudo /bin/bash < /scripts/node${NODE_NUM}.sh"
    elif docker exec ${VM_CID} /bin/bash -c "test -f /scripts/nodes.sh" ; then
      docker exec ${VM_CID} /bin/bash -c "ssh.sh sudo /bin/bash < /scripts/nodes.sh"
    fi
    docker wait ${VM_CID} &
  done
  wait
fi
