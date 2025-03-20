#!/bin/bash

set -e

. ./env.sh
./stop.sh

if [ -z "${IMAGE}" ];
then
  echo "image not set"
  exit 1
fi

/usr/bin/docker run \
  -d \
  --net "{{ .Input.network }}" \
  --name "hoist_{{ .Input.name }}" \
{{- if .Input.syslog }}
  --log-driver syslog \
  --log-opt "tag={{ .Input.name }}" \
{{- end }}
{{- range .Input.volumes }}
  --volume "{{ . }}" \
{{- end }}
{{- range .Input.ports }}
  -p "{{ . }}" \
{{- end }}
{{- range .Input.environment }}
  -e "{{ . }}" \
{{- end }}
{{- if .Input.entrypoint }}
  --entrypoint "{{ .Input.entrypoint }}" \
{{- end }}
  --rm \
  "{{ .Input.image }}" {{if .Input.command }}{{ .Input.command }}{{ end }}
