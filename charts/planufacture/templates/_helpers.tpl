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
{{- $component := default (index .Values $key) (index .Values.microServices $key) -}}
{{- $tag := dig "image" "tag" "" (default (dict) $component) -}}
{{- if $tag -}}
{{- $version = $tag -}}
{{- end -}}
{{- end -}}
{{- $version | toString -}}
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
