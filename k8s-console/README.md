# Chart Helm: k8s-console

Konsola webowa do wielu klastrów Kubernetes. Każde żądanie idzie do API Servera z impersonacją
zalogowanego użytkownika, więc o uprawnieniach decyduje RBAC klastra. Klastry zdalne łączą się
przez agenta (niżej).

Obraz: `docker.io/arturkiwa/k8s-console` (domyślnie tag = `appVersion` chartu).

Najprostsza instalacja (konsola na każdym klastrze): [README w katalogu głównym](../README.md).
Poniżej opis pełny: jedna konsola dla wielu klastrów (agent), własne CA, Prometheus, Hubble.

## Jedna konsola, kilka klastrów (agent)

Konsola stoi na jednym klastrze. Na każdym klastrze zdalnym działa **agent**: ten sam obraz, ten sam
chart, `mode: agent`. Agent sam łączy się do konsoli po HTTPS i trzyma to połączenie. Konsola wysyła
przez nie zapytania, a agent wykonuje je lokalnie: w API swojego klastra (zawsze w imieniu
zalogowanego użytkownika), w Prometheusie i w Hubble Relay.

- Na klastrze zdalnym nic nie jest wystawiane. Potrzebny jest tylko ruch **z klastra zdalnego do adresu
  konsoli** (Ingress / HTTPRoute konsoli).
- Konsola nie zna tokenów ani CA klastrów zdalnych. Agent ma tylko prawo podszywania się pod grupy
  konsoli, tak jak konsola na swoim klastrze.
- Agent przedstawia się kluczem, który generuje konsola. Bez dobrego klucza konsola go odrzuca.

| `mode` | Co instaluje |
|---|---|
| `console` | konsola: Deployment, Service, Secret z konfiguracją, Ingress / HTTPRoute, PVC z historią, klucze agentów; RBAC |
| `agent` | agent: Deployment (bez Service), Secret z kluczem; RBAC |


### Krok po kroku

Wszystko robisz z jednej maszyny (np. bastionu), w katalogu, w którym leżą rozpakowany chart
`k8s-console/` i Twój `values-single.yaml` (ten z hashami haseł). Tych samych dwóch rzeczy używasz na
klastrze głównym i na klastrach zdalnych.

**0. `values-single.yaml`.** Ustaw `image.tag` na wersję chartu. Dopisz adres konsoli (agenty łączą
się pod ten adres) i nazwy klastrów zdalnych:

```yaml
ingress:
  enabled: true
  className: nginx # klasa Ingressu na klastrze głównym (kubectl get ingressclass)
  host: konsola.twoja-domena
agents:
  - name: klaster-b # nazwa dowolna, tak będzie widoczna w konsoli
```

**A. Klaster GŁÓWNY** (kubectl ustawiony na klaster główny)

A1. Zainstaluj albo zaktualizuj konsolę. Helm tworzy przy tym klucz agenta dla każdego klastra z `agents`:

```sh
helm upgrade --install k8s-console ./k8s-console -n k8s-console --create-namespace -f values-single.yaml
```

A2. Wypisz klucz agenta dla `klaster-b` (jedna linia znaków — skopiuj ją):

```sh
kubectl -n k8s-console get secret k8s-console-agent-keys -o jsonpath='{.data.klaster-b}' | base64 -d; echo
```

**B. Klaster ZDALNY `klaster-b`** (przełącz kubectl na ten klaster)

B1. Zainstaluj agenta. W miejsce `WKLEJ-KLUCZ` wklej linię z A2:

```sh
helm install k8s-console-agent ./k8s-console -n k8s-console --create-namespace -f values-single.yaml \
  --set mode=agent \
  --set agent.server=https://konsola.twoja-domena \
  --set agent.cluster=klaster-b \
  --set agent.key=WKLEJ-KLUCZ
```

Dopisz do tego polecenia, jeśli potrzebne:

- certyfikat Ingressu konsoli jest od CA organizacji:
  `--set-file trust.caBundle=/etc/pki/tls/certs/ca-bundle.crt` (RHEL; Debian / Ubuntu:
  `/etc/ssl/certs/ca-certificates.crt`) — plik zaufanych CA z maszyny, na której `curl https://konsola.twoja-domena/healthz` działa;
- Prometheus na tym klastrze (adres: `kubectl get svc -A | grep -i prometheus` → `http://<nazwa>.<namespace>.svc:<port>`):
  `--set agent.prometheus.url=http://<nazwa>.<namespace>.svc:<port>`; z hasłem najpierw
  `kubectl create namespace k8s-console` i
  `kubectl -n k8s-console create secret generic prometheus-haslo --from-literal=password='<hasło>'`,
  potem dopisz `--set agent.prometheus.username=<użytkownik> --set agent.prometheus.passwordSecret.name=prometheus-haslo`;
- Hubble (Cilium): `--set agent.hubble.address=hubble-relay.kube-system.svc:80`.

Jeśli Artifactory wymaga logowania, Secret do rejestru musi istnieć w namespace `k8s-console` także na
tym klastrze (utwórz go przed B1, tak jak przy konsoli).

B2. Sprawdź log agenta — ma być `agent: połączony z konsolą`:

```sh
kubectl -n k8s-console logs deploy/k8s-console-agent
```

Zmiana ustawień agenta później (np. dopisanie CA): `helm upgrade k8s-console-agent ./k8s-console
-n k8s-console --reuse-values --set …` — `--reuse-values` zostawia klucz i resztę ustawień.

**C. Przeglądarka:** na stronie startowej konsoli kafel `klaster-b` — „przez agenta · połączony”.

| W logu agenta | Co zrobić |
|---|---|
| `konsola nie zna tego klastra albo klucz agenta jest inny` | nazwa w `agent.cluster` inna niż w `agents` albo klucz z innej instalacji — powtórz A2 i B1 |
| błąd certyfikatu (nieznane CA) | dopisz `trust.caBundle` (wyżej) przez `helm upgrade … --reuse-values` |
| `nie dotarła do konsoli`, `innym protokołem`, `403`, `426` | konsola i agent w różnych wersjach albo starsze niż 0.2.2 — zaktualizuj oba; od 0.2.2 agent sam omija Ingress, który nie przepuszcza WebSocket |
| `no such host`, `connection refused`, `timeout` | klaster zdalny nie ma drogi do adresu konsoli (DNS, firewall) |

### Dodanie i usunięcie klastra

Nowy klaster: dopisz go do `agents` i powtórz A1, A2, B1, B2. Usunięcie klastra z `agents` i `helm upgrade`
konsoli unieważnia jego klucz; na klastrze zdalnym: `helm uninstall k8s-console-agent -n k8s-console`.

Agent ma tylko prawo podszywania się pod grupy konsoli (`<prefiks><grupa>`) i role dla tych grup, tak
jak konsola na swoim klastrze. Każde połączenie, odrzucenie i rozłączenie agenta trafia do audytu konsoli
(`"phase":"agent"`).

## TLS i własne CA

- **Agent → konsola**: agent weryfikuje certyfikat Ingressu konsoli. Gdy certyfikat jest od CA
  organizacji, dopisz to CA do `trust.caBundle` agenta (albo `trust.existingConfigMap`).
- **`trust.caBundle`** dokłada certyfikaty do systemowej puli CA (zmienna `SSL_CERT_DIR`). Korzystają
  z niej wszystkie połączenia wychodzące: agent → konsola, Prometheus / Thanos, Hubble Relay.
- Konsola i agent nie mają opcji pominięcia weryfikacji certyfikatu.
- **Proxy wyjściowe**: `extraEnv` z `HTTPS_PROXY` i `NO_PROXY`. Usługi w klastrze (`.svc`) i adres API
  wpisz do `NO_PROXY`.
- Połączenie agenta przechodzi przez Ingress jako WebSocket, a gdy Ingress go nie przepuszcza — sam
  przechodzi na zwykłe zapytania HTTP (bez żadnych adnotacji). Agent i konsola co
  20–30 s sprawdzają, czy połączenie żyje, więc bezczynne połączenia nie są zamykane przez load balancer.

## Prometheus, Hubble na klastrze konsoli

Sekcje `localCluster.metrics` i `localCluster.hubble` mają ten sam format co w pliku konfiguracji
konsoli (przykład niżej). Hasło trzymaj w Secrecie: dodaj jego nazwę do
`extraSecretMounts`, a w konfiguracji podaj ścieżkę `/etc/k8s-console/secrets/<secret>/<klucz>`:

```yaml
extraSecretMounts: [prometheus-reader]
localCluster:
  metrics:
    prometheusURL: https://thanos-query.monitoring.svc:9090
    basicAuthUsername: console-reader
    basicAuthPasswordFile: /etc/k8s-console/secrets/prometheus-reader/password
```

Dla klastrów z agentem w konsoli zostają tylko `agents[].metrics.window` i `useForInsights`.

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
usuń go ręcznie, jeśli nie jest potrzebny. Tak samo zostaje Secret z kluczami agentów — po ponownej
instalacji konsoli agenty łączą się bez zmian.

Agent: `helm uninstall k8s-console-agent -n k8s-console` na klastrze zdalnym.
