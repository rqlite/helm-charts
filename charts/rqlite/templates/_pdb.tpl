{{/*
Meta-template for PodDisruptionBudget, similar to _statefulset.tpl.

Unlike Statefulset and Service, we don't fall back to voter PDB configuration for
readonly nodes as it wouldn't be appropriate.

Usage: include "rqlite.renderPDB" (dict "type" "voter|readonly" "ctx" $)
*/}}
{{- define "rqlite.renderPDB" -}}
{{/* Replace our root context with the caller's root context to behave more seamlessly. */}}
{{- $ := .ctx }}
{{/* Where we should look first for chart values, which depends on the type. */}}
{{- $readonly := eq .type "readonly" }}
{{- $values := $readonly | ternary $.Values.readonly $.Values.AsMap }}
{{- $suffix := $readonly | ternary "-readonly" "" }}
{{- $name := tpl (include "rqlite.fullname" $) $ -}}

apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $name }}{{ $suffix }}
  labels:
    {{- include "rqlite.labels" $ | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "rqlite.selectorLabels" $ | nindent 6 }}
      app.kubernetes.io/component: {{ .type }}

  {{- if $values.podDisruptionBudget }}
  {{- tpl (toYaml $values.podDisruptionBudget) $ | nindent 2 }}
  {{- else }}
  {{/*
  The default PDB configuration ensures N/2+1 pods are available (i.e. allows a max of
  N-(N/2+1) to be unavailable).  For clusters with fewer than 3 nodes, we always allow 1
  pod to be unavailable, since this is an explicitly non-HA deployment.

  This is necessary for for voter nodes, but readonly could tolerate more. Still, by
  default we use the same formula for both pools, and leave it up to the user to override
  if they want.
  */}}
  {{- $quorum := (add (div $values.replicaCount 2) 1) }}
  maxUnavailable: {{ max 1 (sub $values.replicaCount $quorum) }}
  {{- end }}
{{- end }}
