#!/bin/bash

set -e

if [ "$( /usr/bin/docker container inspect -f '{{ "{{.State.Status}}" }}' 'hoist_{{ .Input.name }}' )" == "running" ]
then
  exit 0
fi

exit 1

