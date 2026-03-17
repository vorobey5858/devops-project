{{- define "service-template.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-template.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "service-template.name" . -}}
{{- end -}}
{{- end -}}

{{- define "service-template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "service-template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service-template.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "service-template.labels" -}}
helm.sh/chart: {{ include "service-template.chart" . }}
{{ include "service-template.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: commerce-platform
platform.example.io/environment: {{ .Values.environment | quote }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "service-template.configmapName" -}}
{{- printf "%s-config" (include "service-template.fullname" .) -}}
{{- end -}}

{{- define "service-template.secretName" -}}
{{- printf "%s-secrets" (include "service-template.fullname" .) -}}
{{- end -}}

{{- define "service-template.podAnnotations" -}}
{{- $annotations := dict -}}
{{- if .Values.metrics.enabled -}}
{{- $_ := set $annotations "prometheus.io/scrape" "true" -}}
{{- $_ := set $annotations "prometheus.io/path" (.Values.metrics.path | default "/metrics") -}}
{{- $_ := set $annotations "prometheus.io/port" (printf "%v" .Values.containerPort) -}}
{{- end -}}
{{- range $key, $value := .Values.podAnnotations }}
{{- $_ := set $annotations $key $value -}}
{{- end -}}
{{- if $annotations }}
{{ toYaml $annotations }}
{{- end -}}
{{- end -}}

{{- define "service-template.podTemplate" -}}
metadata:
  labels:
    {{- include "service-template.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- $podAnnotations := include "service-template.podAnnotations" . }}
  {{- if $podAnnotations }}
  annotations:
    {{- $podAnnotations | nindent 4 }}
  {{- end }}
spec:
  terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
  {{- with .Values.image.pullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    - name: app
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      {{- with .Values.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      ports:
        - name: http
          containerPort: {{ .Values.containerPort }}
          protocol: TCP
      {{- with .Values.env }}
      env:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if or .Values.configmap.enabled .Values.secret.enabled .Values.secret.existingSecretName .Values.envFrom }}
      envFrom:
        {{- if .Values.configmap.enabled }}
        - configMapRef:
            name: {{ include "service-template.configmapName" . }}
        {{- end }}
        {{- if .Values.secret.enabled }}
        - secretRef:
            name: {{ include "service-template.secretName" . }}
        {{- else if .Values.secret.existingSecretName }}
        - secretRef:
            name: {{ .Values.secret.existingSecretName }}
        {{- end }}
        {{- with .Values.envFrom }}
{{ toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
      readinessProbe:
        {{- toYaml .Values.readinessProbe | nindent 8 }}
      livenessProbe:
        {{- toYaml .Values.livenessProbe | nindent 8 }}
      securityContext:
        {{- toYaml .Values.securityContext | nindent 8 }}
      resources:
        {{- toYaml .Values.resources | nindent 8 }}
      {{- with .Values.extraVolumeMounts }}
      volumeMounts:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with .Values.extraVolumes }}
  volumes:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- range $constraint := . }}
    - maxSkew: {{ $constraint.maxSkew }}
      topologyKey: {{ $constraint.topologyKey | quote }}
      whenUnsatisfiable: {{ $constraint.whenUnsatisfiable | quote }}
      {{- if $constraint.minDomains }}
      minDomains: {{ $constraint.minDomains }}
      {{- end }}
      {{- with $constraint.nodeAffinityPolicy }}
      nodeAffinityPolicy: {{ . | quote }}
      {{- end }}
      {{- with $constraint.nodeTaintsPolicy }}
      nodeTaintsPolicy: {{ . | quote }}
      {{- end }}
      {{- if $constraint.labelSelector }}
      labelSelector:
        {{- toYaml $constraint.labelSelector | nindent 8 }}
      {{- else }}
      labelSelector:
        matchLabels:
          {{- include "service-template.selectorLabels" $ | nindent 10 }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
