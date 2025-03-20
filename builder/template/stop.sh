#!/bin/bash

set -e

/usr/bin/docker stop "hoist_{{ .Input.name }}" || true
/usr/bin/docker rm "hoist_{{ .Input.name }}" || true

