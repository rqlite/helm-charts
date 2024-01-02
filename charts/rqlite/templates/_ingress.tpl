{{/*
Meta-template for K8s Ingress, similar to _statefulset.tpl.

Unlike Statefulset and Service, we don't fall back to voter Ingress configuration for
readonly nodes as it wouldn't be appropriate.

Usage: include "rqlite.renderIngress" (dict "type" "voter|readonly" "ctx" $)
*/}}
{{- define "rqlite.renderIngress" -}}
{{/* Replace our root context with the caller's root context to behave more seamlessly. */}}
{{- $ := .ctx }}
{{/* Where we should look first for chart values, which depends on the type. */}}
{{- $readonly := eq .type "readonly" }}
{{- $values := $readonly | ternary $.Values.readonly $.Values.AsMap }}
{{- $suffix := $readonly | ternary "-readonly" "" }}
{{- $config := $.Values.config }}
{{- $name := tpl (include "rqlite.fullname" $) $ -}}

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $name }}{{ $suffix }}
  labels:
    {{- include "rqlite.labels" $ | nindent 4 }}
    {{- with dig "ingress" "extraLabels" dict $values }}
      {{ toYaml . | nindent 4 }}
    {{- end }}
    app.kubernetes.io/component: {{ .type }}
  {{- with dig "ingress" "annotations" dict $values }}
  annotations:
    {{- toYaml . | nindent 4 }}
    {{- if $config.tls.client.enabled }}
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    {{- end }}
  {{- end }}
spec:
{{- with dig "ingress" "tls" false $values }}
  tls:
  {{- range . }}
    - hosts:
      {{- range .hosts }}
        - {{ . | quote }}
      {{- end }}
      secretName: {{ .secretName }}
  {{- end }}
{{- end }}
{{/* We loop over hosts so ensure we have at least one, even if it's a dummy value */}}
{{- $hosts := coalesce (dig "ingress" "hosts" list $values) (list "") }}
  rules:
    {{- range $hosts }}
    - http:
        paths:
          - path: {{ dig "ingress" "path" "" $values | default "/" }}
            pathType: {{ dig "ingress" "pathType" "" $values | default "Prefix" }}
            backend:
              service:
                name: {{ $name }}{{ $suffix }}
                port:
                  name: http

      {{- if . }}
      host: {{ . }}
      {{- end }}
    {{- end }}
{{- end }}
