{{/*
This is a meta-template for the rqlite StatefulSet, which is used for both voter and
readonly pools.  The type ("voter" or "readonly") is passed which influences where values
are pulled from. In the case of the readonly type, values are checked under
.Values.readonly first, falling back to the top-level keys in .Values if missing.

Usage: include "rqlite.renderStatefulSet" (dict "type" "voter|readonly" "ctx" $)
*/}}
{{- define "rqlite.renderStatefulSet" -}}
{{/* Replace our root context with the caller's root context to behave more seamlessly. */}}
{{- $ := .ctx }}
{{/* Where we should look first for chart values, which depends on the type. */}}
{{- $readonly := eq .type "readonly" }}
{{- $values := $readonly | ternary $.Values.readonly $.Values.AsMap }}
{{- $suffix := $readonly | ternary "-readonly" "" }}
{{- $config := $.Values.config }}
{{- $name := tpl (include "rqlite.fullname" $) $ -}}
{{- include "rqlite.generateSecrets" $ -}}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ $name }}{{ $suffix }}
  labels:
    {{- include "rqlite.labels" $ | nindent 4 }}
    app.kubernetes.io/component: {{ .type }}
spec:
  replicas: {{ dig "replicaCount" $.Values.replicaCount $values }}
  # rqlite is tolerant of all nodes coming up simultaneously, so we set the pod management
  # policy to parallel to allow fast scaling.
  podManagementPolicy: Parallel
  updateStrategy:
    {{- tpl (toYaml (dig "updateStrategy" $.Values.updateStrategy $values)) $ | nindent 4 }}
  selector:
    matchLabels:
      {{- include "rqlite.selectorLabels" $ | nindent 6 }}
      app.kubernetes.io/component: {{ .type }}
  serviceName: {{ $name }}-headless{{ $suffix }}

  template:
    metadata:
      labels:
        {{- include "rqlite.selectorLabels" $ | nindent 8 }}
        app.kubernetes.io/component: {{ .type }}
        {{- with dig "podLabels" $.Values.podLabels $values}}
          {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with dig "podAnnotations" $.Values.podAnnotations $values }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- if $.Values.serviceAccount.name }}
      serviceAccountName: {{ $.Values.serviceAccount.name }}
      {{- else }}
      automountServiceAccountToken: false
      {{- end }}

      terminationGracePeriodSeconds: {{ dig "terminationGracePeriodSeconds" $.Values.terminationGracePeriodSeconds $values }}

      {{- with dig "podSecurityContext" $.Values.podSecurityContext $values }}
      securityContext:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      {{- with dig "nodeSelector" $.Values.nodeSelector $values }}
      nodeSelector:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      {{- with dig "tolerations" $.Values.tolerations $values }}
      tolerations:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      {{- with dig "affinity" $.Values.affinity $values }}
      affinity:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      {{- with dig "topologySpreadConstraints" $.Values.topologySpreadConstraints $values }}
      topologySpreadConstraints:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      {{- with dig "pullSecrets" $.Values.image.pullSecrets $values }}
      imagePullSecrets:
        {{- tpl (toYaml .) $ | nindent 8 }}
      {{- end }}

      volumes:
        - name: secrets
          secret:
            secretName: {{ $name }}
            defaultMode: 288 # 0400
        - name: extra
          secret:
            secretName: {{ $name }}-extra
            defaultMode: 288 # 0400
        - name: config-peers
          configMap:
            name: {{ $name }}-peers
      {{- if $config.tls.node.secretName }}
        - name: node-tls
          secret:
            secretName: {{ $config.tls.node.secretName }}
            defaultMode: 288 # 0400
      {{- end }}
      {{- if $config.tls.node.caSecretName }}
        - name: node-tls-ca
          secret:
            secretName: {{ $config.tls.node.caSecretName }}
            defaultMode: 288 # 0400
      {{- end }}
      {{- if $config.tls.client.secretName }}
        - name: client-tls
          secret:
            secretName: {{ $config.tls.client.secretName }}
            defaultMode: 288 # 0400
      {{- end }}
      {{- if $config.tls.client.caSecretName }}
        - name: client-tls-ca
          secret:
            secretName: {{ $config.tls.client.caSecretName }}
            defaultMode: 288 # 0400
      {{- end }}
      {{- if not (dig "persistence" "enabled" $.Values.persistence.enabled $values) }}
        - name: storage
          emptyDir: {}
      {{- end }}
      containers:
        - name: rqlite
          {{- with dig "image" $.Values.image $values }}
          image: {{ .repository }}:{{ .tag | default $.Chart.AppVersion }}
          {{- with .pullPolicy }}
          imagePullPolicy: {{ . }}
          {{- end }}
          {{- end }}
          # Override the default docker entrypoint script so we can add our own
          # custom startup logic ahead of rqlited. Afterward we exec the original
          # entrypoint script with all the required arguments.
          command: ["/bin/sh", "-c"]
          args:
            - |-
              # If we're using static peers, copy the chart-generated peers file into
              # place. But first remove any existing peers file, which we do regardless as
              # in normal operation we use DNS discovery.
              rm -f /rqlite/raft/peers.info
              if [ "$RQLITE_USE_STATIC_PEERS" = "true" ]; then
                echo "WARNING: Using generated static peers. This is a recovery procedure and must be reverted after service is restored."
                cat /config/peers/peers.json
                mkdir -p /rqlite/raft
                cp /config/peers/peers.json /rqlite/raft
              fi
              # Exec original entrypoint and pass all arguments through, including $0
              # which is actually the first argument due to this inline script being
              # executed as a command string.
              exec /bin/docker-entrypoint.sh "$0" "$@"

            # All arguments after this point are passed through to docker-entrypoint.sh
            # by the init script above.
            {{- if $config.users }}
            - -auth=/config/sensitive/users.json
            - -join-as=_system_rqlite
            {{- end }}
            {{- if $config.tls.node.enabled }}
            {{- $basefile := empty $config.tls.node.secretName | ternary "/config/sensitive/node" "/config/node-tls/tls" }}
            - -node-cert={{ $basefile }}.crt
            - -node-key={{ $basefile }}.key
            {{- if $config.tls.node.verifyServerName }}
            - -node-verify-server-name={{ $config.tls.node.verifyServerName }}
            {{- else if kindIs "invalid" $config.tls.node.verifyServerName }}
              {{- fail "config.tls.node.verifyServerName must be defined when config.tls.node.enabled is true" }}
            {{- end }}
            {{- if $config.tls.node.caSecretName }}
            - -node-ca-cert=/config/node-tls-ca/ca.crt
            {{- else if $config.tls.node.ca }}
            - -node-ca-cert=/config/sensitive/node-ca.crt
            {{- end }}
            {{- if $config.tls.node.mutual }}
            - -node-verify-client
            {{- end }}
            {{- if $config.tls.node.insecureSkipVerify }}
            - -node-no-verify
            {{- end }}
            {{- end }}

            {{- if $config.tls.client.enabled }}
            {{- $basefile := empty $config.tls.client.secretName | ternary "/config/sensitive/client" "/config/client-tls/tls" }}
            - -http-cert={{ $basefile }}.crt
            - -http-key={{ $basefile }}.key
            {{- if $config.tls.client.caSecretName }}
            - -http-ca-cert=/config/client-tls-ca/ca.crt
            {{- else if $config.tls.client.ca }}
            - -http-ca-cert=/config/sensitive/client-ca.crt
            {{- end }}
            {{- if $config.tls.client.mutual }}
            # Disabled for now. https://github.com/rqlite/rqlite/issues/1508
            # - -http-verify-client
            {{- end }}
            {{- end }}
            - -disco-mode=dns-srv
            - -disco-config={"name":"{{ $name }}-headless","service":"raft"}
            {{- if $readonly }}
            - -raft-cluster-remove-shutdown=true
            - -raft-non-voter=true
            {{- else }}
            # This is value is interpolated by the Kubelet using the Kubernetes
            # substitution syntax instead of being rendered by the Helm chart to ensure
            # that changes to replicaCount doesn't result in a rolling restart of all pods
            # in the StatefulSet.
            - -bootstrap-expect=$(RQLITE_VOTER_REPLICA_COUNT)
            {{- if dig "backup" "autoBackup" "enabled" false $config }}
            - -auto-backup=/config/sensitive/backup.json
            {{- end }}
            {{- if dig "backup" "autoRestore" "enabled" false $config }}
            - -auto-restore=/config/sensitive/restore.json
            {{- end }}
            {{- end }}
            - -join-interval=1s
            - -join-attempts=120
            - -raft-shutdown-stepdown
            {{- with $.Values.extraArgs }}
              {{- tpl (toYaml .) $ | nindent 12 }}
            {{- end }}
          {{- with dig "resources" $.Values.resources $values }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            - containerPort: 4001
              name: http
            - containerPort: 4002
              name: raft
          env:
            - name: DATA_DIR
              value: "/rqlite"
            - name: RQLITE_USE_STATIC_PEERS
              valueFrom:
                configMapKeyRef:
                  name: {{ $name }}-peers
                  key: use-static-peers
            {{- if not $readonly }}
            - name: RQLITE_VOTER_REPLICA_COUNT
              valueFrom:
                configMapKeyRef:
                  name: {{ $name }}-peers
                  key: voter-replica-count
            {{- end }}
            {{- with dig "extraEnv" $.Values.extraEnv $values }}
              {{- tpl (toYaml .) $ | nindent 12 }}
            {{- end }}

          {{- with dig "securityContext" $.Values.securityContext $values }}
          securityContext:
            {{- tpl (toYaml .) $ | nindent 12 }}
          {{- end }}

          {{- with dig "readinessProbe" $.Values.readinessProbe $values }}
          readinessProbe:
            {{- tpl (toYaml .) $ | nindent 12 -}}
          {{- end }}

          {{- with dig "startupProbe" $.Values.startupProbe $values }}
          startupProbe:
            {{- tpl (toYaml .) $ | nindent 12 -}}
          {{- end }}

          {{- with dig "livenessProbe" $.Values.livenessProbe $values }}
          livenessProbe:
            {{- tpl (toYaml .) $ | nindent 12 -}}
          {{- end }}

          lifecycle:
            # Sleep to hold off SIGTERM until after K8s endpoint list has had a chance to
            # reflect removal of this pod, otherwise traffic could continue to be directed
            # to the pod's IP after we have terminated. This is a fairly narrow race
            # condition with K8s so a couple seconds is enough to avoid it.
            preStop:
              exec:
                command:
                  - sleep
                  - "2"
          volumeMounts:
            - name: storage
              mountPath: /rqlite
            - name: secrets
              mountPath: /config/sensitive
            - name: extra
              mountPath: /config/extra
            - name: config-peers
              mountPath: /config/peers
            {{- if $config.tls.node.secretName }}
            - name: node-tls
              mountPath: /config/node-tls
            {{- end }}
            {{- if $config.tls.node.caSecretName }}
            - name: node-tls-ca
              mountPath: /config/node-tls-ca
            {{- end }}
            {{- if $config.tls.client.secretName }}
            - name: client-tls
              mountPath: /config/client-tls
            {{- end }}
            {{- if $config.tls.client.caSecretName }}
            - name: client-tls-ca
              mountPath: /config/client-tls-ca
            {{- end }}
  {{- $persistence := dig "persistence" $.Values.persistence $values }}
  {{- if $persistence.enabled }}
  volumeClaimTemplates:
    - kind: PersistentVolumeClaim
      apiVersion: v1
      metadata:
        name: storage
        {{- with $persistence.labels }}
        labels:
          {{- toYaml . | nindent 10 }}
        {{- end }}
      spec:
        {{- with $persistence.storageClassName }}
        storageClassName: {{ . }}
        {{- end }}
        {{- with $persistence.accessModes }}
        accessModes:
          {{- toYaml . | nindent 10 }}
        {{- end }}
        resources:
          requests:
            storage: {{ $persistence.size | default "10Gi" }}
  {{- end }}
{{- end }}
