#!/bin/bash

set -e

{{ if .Input.kv_update }}
if [ -z "${WATCHER_DATA}" ];
then
  export IMAGE="{{ .Input.image }}:{{ .Input.image_tag }}"
else
  TAG=$(cat ${WATCHER_DATA} | jq -r 'if has("container.{{ .Input.name }}.tag") then ."container.{{ .Input.name }}.tag" else "{{ .Input.image_tag }}" end')

  if [ -z "${TAG}" ];
  then
    TAG="{{ .Input.image_tag }}"
  fi

  export IMAGE="{{ .Input.image }}:${TAG}"
fi
{{ else }}
export IMAGE="{{ .Input.image }}:{{ .Input.image_tag }}"
{{ end }}

