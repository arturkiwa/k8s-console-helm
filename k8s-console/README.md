# Chart Helm: k8s-console

Konsola webowa do wielu klastrów Kubernetes. Każde żądanie idzie do API Servera z impersonacją
zalogowanego użytkownika, więc o uprawnieniach decyduje RBAC klastra. Na klastrach nie ma agentów.

Obraz: `docker.io/arturkiwa/k8s-console` (domyślnie tag = `appVersion` chartu).

Najprostsza instalacja (konsola na każdym klastrze): [README w katalogu głównym](../README.md).
Poniżej opis pełny: jedna konsola dla wielu klastrów, własne CA, Prometheus, Hubble.

## Tryby

| `mode` | Co instaluje | Gdzie |
|---|---|---|
| `console` | Deployment, Service, Secret z konfiguracją, opcjonalnie Ingress / HTTPRoute, PVC z historią; RBAC na tym klastrze | klaster, na którym działa konsola |
| `target` | tylko RBAC: ServiceAccount z prawem impersonacji, role dla grup, Secret z tokenem | każdy klaster zarządzany zdalnie |

## Instalacja: jedna konsola, kilka klastrów

**1. Hashe haseł** (bcrypt):

```sh
docker run --rm -i docker.io/arturkiwa/k8s-console:0.1.0 hash-password
```

**2. Każdy klaster zdalny** — RBAC i token:

```sh
helm install k8s-console k8s-console-0.1.0.tgz -n k8s-console --create-namespace \
  --kube-context <klaster-zdalny> --set mode=target
```

NOTES po instalacji pokazują, jak przenieść token i `ca.crt` do Secretu w klastrze konsoli:

```sh
kubectl --context <klaster-zdalny> -n k8s-console get secret k8s-console-impersonator-token \
  -o jsonpath='{.data.token}' | base64 -d > token
kubectl --context <klaster-zdalny> -n k8s-console get secret k8s-console-impersonator-token \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
kubectl --context <klaster-konsoli> -n k8s-console create secret generic k8s-console-<nazwa> \
  --from-file=token --from-file=ca.crt
rm token ca.crt
```

**3. Konsola** — `values-console.yaml`:

```yaml
identity:
  users:
    - { username: viewer, passwordHash: "$2a$10$…", groups: [poc-viewers] }
    - { username: operator, passwordHash: "$2a$10$…", groups: [poc-operators] }
localCluster:
  name: mgmt
remoteClusters:
  - name: klaster-a
    server: https://api.klaster-a.example.internal:6443
    tokenSecret: k8s-console-klaster-a
  - name: klaster-b
    server: https://10.20.30.40:6443 # VIP — nazwa w certyfikacie inna niż adres
    tlsServerName: api.klaster-b.example.internal
    tokenSecret: k8s-console-klaster-b
    caKey: "" # certyfikat API od CA organizacji → zaufanie z trust.caBundle
trust:
  caBundle: |
    -----BEGIN CERTIFICATE-----
    …CA główne i pośrednie organizacji…
    -----END CERTIFICATE-----
ingress:
  enabled: true
  className: nginx
  host: console.example.internal
  tls: { secretName: console-tls }
```

```sh
helm install k8s-console k8s-console-0.1.0.tgz -n k8s-console --create-namespace \
  --kube-context <klaster-konsoli> -f values-console.yaml
```

Prefiks (`identity.prefix`) i nazwy grup (`groups`) muszą być takie same we wszystkich instalacjach,
bo RBAC na każdym klastrze nadaje uprawnienia grupom `<prefiks><grupa>`.

## TLS i własne CA

- **API Server klastra zdalnego** jest zawsze po HTTPS. Domyślnie konsola weryfikuje go CA z Secretu
  (`ca.crt` z tokenu ServiceAccountu, czyli CA klastra). Gdy API jest za load balancerem z certyfikatem
  od CA organizacji, ustaw `caKey: ""`. Wtedy weryfikacja idzie pulą systemową razem z `trust.caBundle`.
- **`trust.caBundle`** (albo `trust.existingConfigMap`) dokłada certyfikaty do systemowej puli CA
  (zmienna `SSL_CERT_DIR`). Korzystają z niej wszystkie połączenia wychodzące bez własnego `caFile`:
  API Servery, Prometheus / Thanos, Hubble Relay. `caFile` przy połączeniu dokłada swoje CA do tej
  puli, a nie ją zastępuje.
- **`tlsServerName`** — gdy łączysz się po IP albo VIP, a certyfikat ma inną nazwę.
- Konsola nie ma opcji pominięcia weryfikacji certyfikatu.
- **Proxy wyjściowe**: `extraEnv` z `HTTPS_PROXY` i `NO_PROXY`. Adresy API Serverów i usług w klastrze
  zwykle trafiają do `NO_PROXY`.
- Błędy połączenia są opisane na stronie startowej konsoli przy klastrze: nieznane CA, nazwa spoza
  certyfikatu, DNS, proxy, timeout.

## Prometheus, Hubble

Sekcje `metrics` i `hubble` przy klastrze mają ten sam format co w pliku konfiguracji konsoli
(pliku konfiguracji konsoli). Hasło albo certyfikaty klienta trzymaj w Secrecie: dodaj jego nazwę do
`extraSecretMounts`, a w konfiguracji podaj ścieżkę `/etc/k8s-console/secrets/<secret>/<klucz>`:

```yaml
extraSecretMounts: [prometheus-reader]
localCluster:
  metrics:
    prometheusURL: https://thanos-query.monitoring.svc:9090
    basicAuthUsername: console-reader
    basicAuthPasswordFile: /etc/k8s-console/secrets/prometheus-reader/password
```

## Opcjonalne uprawnienia

| Wartość | Daje | Domyślnie |
|---|---|---|
| `rbac.extendedRead` | odczyt zasobów spoza roli `view` (StorageClass, CRD, webhooki, Istio, Cilium, Gateway API…) | tak |
| `rbac.collector` | historia zużycia z metrics-server (Rekomendacje bez Prometheusa) | tak |
| `rbac.argocdRead` | operatorzy: odczyt aplikacji ArgoCD (Historia: kto zarządza obiektem) | nie |
| `rbac.rbacRead` | operatorzy: odczyt ról i powiązań (Bezpieczeństwo: uprawnienia kont, „kto może”) — ujawnia model uprawnień klastra | nie |

`allowMutations: false` (domyślnie przy każdym klastrze) blokuje w konsoli wszystkie operacje zmieniające
stan, niezależnie od RBAC. Dobre na start w nowym środowisku.

## Odinstalowanie

`helm uninstall k8s-console -n k8s-console`. PVC z historią zostaje (`helm.sh/resource-policy: keep`),
usuń go ręcznie, jeśli nie jest potrzebny.
