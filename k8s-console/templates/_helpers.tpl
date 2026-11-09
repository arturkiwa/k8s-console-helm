{{- define "kc.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "kc.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "kc.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "kc.sa" -}}
{{- default (printf "%s-impersonator" (include "kc.fullname" .)) .Values.serviceAccount.name -}}
{{- end -}}

{{- define "kc.image" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) -}}
{{- end -}}
{{- end -}}

{{/* grupy z prefiksem: viewers / operators / collector */}}
{{- define "kc.group" -}}
{{- printf "%s%s" $.root.Values.identity.prefix $.name -}}
{{- end -}}

{{- define "kc.tls" -}}
{{- if not (kindIs "invalid" .Values.session.secureCookie) -}}
{{- .Values.session.secureCookie -}}
{{- else if and .Values.ingress.enabled .Values.ingress.tls.secretName -}}
true
{{- else if and .Values.httpRoute.enabled .Values.httpRoute.tls -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/* opcjonalne sekcje klastra: metrics / hubble przepisane bez zmian */}}
{{- define "kc.clusterExtras" -}}
{{- $out := dict -}}
{{- if .metrics }}{{ $_ := set $out "metrics" .metrics }}{{ end -}}
{{- if .hubble }}{{ $_ := set $out "hubble" .hubble }}{{ end -}}
{{- toJson $out -}}
{{- end -}}
