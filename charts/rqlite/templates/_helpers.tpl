{{/*
Expand the name of the chart.
*/}}
{{- define "rqlite.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "rqlite.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "rqlite.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rqlite.labels" -}}
helm.sh/chart: {{ include "rqlite.chart" . }}
{{ include "rqlite.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "rqlite.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rqlite.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
Generates internal passwords used for health probes as well a rqlite system user for
cluster joining.

Passwords are randomly generated, but in order to ensure consistency between template
files, we (ab)use the .Release namespace to hold the values (under .Release.rqlite).
Finally, to ensure consistency across upgrades, the generated values are persisted in a
K8s Secret (rendered in secrets.yaml)
*/}}
{{- define "rqlite.generateSecrets" -}}
  {{- if not (index .Release "secrets") -}}
    {{- $name := tpl (include "rqlite.fullname" .) $ -}}
    {{- $obj := (lookup "v1" "Secret" .Release.Namespace (printf "%s-internal" $name)) | default dict }}
    {{- $secrets := (get $obj "data") | default dict }}
    {{- $_ := set .Release "rqlite" (dict
          "probeUser" "_system_probes"
          "probePassword" ((get $secrets "probePassword" | b64dec) | default (randAlphaNum 32))
          "rqliteUser" "_system_rqlite"
          "rqlitePassword" ((get $secrets "rqlitePassword" | b64dec) | default (randAlphaNum 32))
        )
    }}
    {{- /* Construct the HTTP authorization header as a convenience for health probes */ -}}
    {{- $creds := printf "_system_probes:%s" .Release.rqlite.probePassword -}}
    {{- $_ := set .Release.rqlite "probeBasicAuthHeader" (
          printf "Basic %s" ($creds | b64enc)
        )
    -}}
  {{- end }}
{{- end }}

{{/*
Renders TLS certificates as defined in either config.tls.node or config.tls.client.  The
subsection name ("node" or "client") is held the value key of the passed dict.

Usage: include "rqlite.renderTLSFiles" (dict "value" "node|client" "context" $)
*/}}
{{- define "rqlite.renderTLSFiles" -}}
  {{- $section := get .context.Values.config.tls .value -}}
  {{- $files := dict }}
  {{- if and $section.enabled (empty $section.secretName) -}}
    {{- if or (empty $section.cert) (empty $section.key) }}
      {{- fail (printf "when config.tls.%s.enabled is true and config.tls.%s.secretName is not defined, both config.tls.%s.cert and config.tls.%s.key are required" .value .value .value .value) }}
    {{- end }}
    {{- with $section.cert -}}
      {{- $_ := set $files (printf "%s.crt" $.value) . }}
    {{- end -}}
    {{- with $section.key -}}
      {{- $_ := set $files (printf "%s.key" $.value) . }}
    {{- end -}}
  {{- end }}

  {{- if $section.enabled }}
    {{- with $section.ca }}
      {{- $_ := set $files (printf "%s-ca.crt" $.value) . }}
    {{- end }}
  {{- end }}

  {{- if $files }}
    {{- $files | toYaml }}
  {{- end }}
{{- end }}
