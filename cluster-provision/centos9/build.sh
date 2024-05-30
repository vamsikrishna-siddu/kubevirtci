#!/bin/bash -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]] || [[ "$ARCH" == "amd64" ]] ; then
  ARCH="amd64"
fi

centos_version="$(cat $DIR/version | tr -d '\n')"

docker build --build-arg centos_version=$centos_version --build-arg ARCH=$ARCH . -t quay.io/kubevirtci/centos9
