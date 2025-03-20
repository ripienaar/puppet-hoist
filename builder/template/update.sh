#!/bin/bash

set -e

. ./env.sh

if [ -z "${IMAGE}" ];
then
  echo "image not set"
  exit 1
fi

/usr/bin/docker pull "${IMAGE}"
