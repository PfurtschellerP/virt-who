{{/*
Expand the chart name.
*/}}
{{- define "virt-who.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "virt-who.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "virt-who.selectorLabels" -}}
app.kubernetes.io/name: {{ include "virt-who.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Chart labels.
*/}}
{{- define "virt-who.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "virt-who.selectorLabels" . }}
app.kubernetes.io/version: {{ include "virt-who.imageTag" . | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Image tag, defaulting to the chart appVersion.
*/}}
{{- define "virt-who.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion }}
{{- end }}

{{/*
Full image reference. A digest takes precedence over the tag.
*/}}
{{- define "virt-who.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (include "virt-who.imageTag" .) }}
{{- end }}
{{- end }}

{{/*
Name of the Secret holding the reporter credentials.
*/}}
{{- define "virt-who.secretName" -}}
{{- .Values.rhsm.existingSecret | default (printf "%s-credentials" (include "virt-who.fullname" .)) }}
{{- end }}
