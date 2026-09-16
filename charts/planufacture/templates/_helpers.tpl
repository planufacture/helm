{{/*
Expand the name of the chart.
*/}}
{{- define "planufacture.name" -}}
{{- $name := default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- if .key }}
{{- printf "%s-%s" $name .key | kebabcase | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name }}
{{- end }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "planufacture.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default (include "planufacture.name" . ) .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "planufacture.chart" -}}
{{- printf "%s" .Chart.Name | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Version label for a component.

Resolves to the component's OWN image tag (microServices.<key>.image.tag, or
<key>.image.tag for mongo/axonserver) and only falls back to .Chart.AppVersion
when the component has no tag of its own. Set "versionKey" in the context to point
at a different component's tag (e.g. the axonserver-gui Service reports axonserver's).

This matters because these labels land in pod templates: appVersion tracks the UI
version, so using it everywhere made a UI bump change every pod template hash and
needlessly roll every Deployment and StatefulSet.
*/}}
{{- define "planufacture.version" -}}
{{- $version := .Chart.AppVersion -}}
{{- $key := default .key .versionKey -}}
{{- if $key -}}
{{/* Some callers pass a kebab-cased key (secret-mongo-micro-services.yaml,
     job-mongo-accounts.yaml, stateful-set-mongo.yaml), so try both spellings. */}}
{{- $camelKey := $key | camelcase | untitle -}}
{{- $component := "" -}}
{{- range $candidate := list (index .Values.microServices $key) (index .Values.microServices $camelKey) (index .Values $key) -}}
{{- if and (not $component) (kindIs "map" $candidate) -}}
{{- $component = $candidate -}}
{{- end -}}
{{- end -}}
{{- $tag := "" -}}
{{- if $component -}}
{{- $image := get $component "image" -}}
{{- if kindIs "map" $image -}}
{{- $tag = get $image "tag" | toString -}}
{{- end -}}
{{- end -}}
{{- if $tag -}}
{{- $version = $tag -}}
{{- end -}}
{{- end -}}
{{/* Image tags are not guaranteed to be valid label values — a semver build-metadata
     tag like 1.2.3+abc, or one over 63 chars, would fail API validation on every
     labelled resource. Sanitise rather than let a tag break the whole upgrade. */}}
{{- $safe := regexReplaceAll "[^A-Za-z0-9_.-]" ($version | toString) "_" -}}
{{- $safe | trunc 63 | trimAll "-._" -}}
{{- end }}

{{/*
Whether a component is enabled.

Components are on unless they opt out: a missing `enabled` key means enabled, so
only an explicit `enabled: false` switches one off. Pass the component's own
values map (e.g. .Values.microServices.diomacConnector) as the context. Returns
a non-empty string when enabled, so callers can use it directly in an `if`.

A context that is not a map counts as disabled — the component is absent, or an
env has nulled it out (`diomacConnector:` with no body, which Helm's coalesce
drops from the merged values entirely). That spelling is the obvious way to say
"we don't run this", so it has to mean off rather than render a half-built
resource that dies on a nil pointer.

`enabled` is honoured as a string too: `--set-string` and quoted YAML both
produce one, and every non-empty string is truthy in Go templates — "false"
included, which would silently leave the component on.
*/}}
{{- define "planufacture.componentEnabled" -}}
{{- if kindIs "map" . -}}
{{- if hasKey . "enabled" -}}
{{- $enabled := .enabled -}}
{{- if kindIs "string" $enabled -}}
{{- $enabled = not (has (lower $enabled) (list "" "false" "no" "off" "0")) -}}
{{- end -}}
{{- if $enabled -}}true{{- end -}}
{{- else -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "planufacture.labels" -}}
helm.sh/chart: {{ include "planufacture.chart" . }}
{{ include "planufacture.selectorLabels" . }}
{{- $version := include "planufacture.version" . }}
{{- if $version }}
app.kubernetes.io/version: {{ $version | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "planufacture.selectorLabels" -}}
app.kubernetes.io/name: {{ include "planufacture.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "planufacture.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "planufacture.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
