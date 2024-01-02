{{/*
Meta-template for K8s Services, similar to _statefulset.tpl.

Usage: include "rqlite.renderService" (dict "type" "voter|readonly" "ctx" $)
*/}}
{{- define "rqlite.renderService" -}}
{{/* Replace our root context with the caller's root context to behave more seamlessly. */}}
{{- $ := .ctx }}
{{/* Where we should look first for chart values, which depends on the type. */}}
{{- $readonly := eq .type "readonly" }}
{{- $values := $readonly | ternary $.Values.readonly $.Values.AsMap }}
{{- $suffix := $readonly | ternary "-readonly" "" }}
{{- $config := $.Values.config }}
{{- $name := tpl (include "rqlite.fullname" $) $ -}}
{{- $serviceType := dig "service" "type" $.Values.service.type $values | default "ClusterIP" }}

{{- $clientPort := dig "service" "port" $.Values.service.port $values | default ($config.tls.client.enabled | ternary 443 80) }}

# Client-facing Service
kind: Service
apiVersion: v1
metadata:
  name: {{ $name }}{{ $suffix }}
  labels:
    {{- include "rqlite.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .type }}
  {{- with dig "service" "annotations" $.Values.service.annotations $values }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: {{ $serviceType }}
  {{- with dig "service" "clusterIP" $.Values.service.clusterIP $values }}
  clusterIP: {{ . }}
  {{- end }}

  {{- with dig "service" "ipFamilyPolicy" $.Values.service.ipFamilyPolicy $values }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- with dig "service" "ipFamilies" $.Values.service.ipFamilies $values }}
  ipFamilies:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  selector:
    {{- include "rqlite.selectorLabels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .type }}
  ports:
    - name: http
      appProtocol: {{ $config.tls.client.enabled | ternary "https" "http" }}
      protocol: TCP
      port: {{ $clientPort }}
      targetPort: http
      {{- if ne $serviceType "ClusterIP" }}
      {{- /* This is an exception to the "inherits from voter configuration" rule: node ports must be unique. */}}
      {{- with dig "service" "nodePort" 0 $values }}
      nodePort: {{ . }}
      {{- end }}
      {{- end }}
---
# Headless service for discovery
kind: Service
apiVersion: v1
metadata:
  name: {{ $name }}-headless{{ $suffix }}
  labels:
    {{- include "rqlite.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .type }}
  {{- with dig "service" "annotations" $.Values.service.annotations $values }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  type: ClusterIP
  clusterIP: None
  publishNotReadyAddresses: True

  {{- with dig "service" "ipFamilyPolicy" $.Values.service.ipFamilyPolicy $values }}
  ipFamilyPolicy: {{ . }}
  {{- end }}
  {{- with dig "service" "ipFamilies" $.Values.service.ipFamilies $values }}
  ipFamilies:
    {{- toYaml . | nindent 4 }}
  {{- end }}

  selector:
    {{- include "rqlite.selectorLabels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .type }}
  ports:
    - name: http
      protocol: TCP
      port: {{ $clientPort }}
      targetPort: http
    - name: raft
      protocol: TCP
      port: 4002
      targetPort: raft
{{- end }}
