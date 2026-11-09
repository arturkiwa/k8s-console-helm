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

Potrzebujesz: katalogu z chartem (`k8s-console/`) i `values-single.yaml` z wklejonymi hashami — tych
samych co przy instalacji konsoli — oraz `kubectl` i `helm` z dostępem do obu klastrów.

**1. Konsola musi mieć adres osiągalny z klastrów zdalnych.** Agent łączy się do konsoli, więc konsola
potrzebuje Ingressu (albo HTTPRoute). Dopisz do `values-single.yaml`:

```yaml
ingress:
  enabled: true
  className: nginx # klasa Ingressu na klastrze konsoli
  host: konsola.example.internal # nazwa z DNS
  tls: { secretName: konsola-tls } # Secret z certyfikatem (w namespace k8s-console); bez TLS: usuń linię
```

**2. Dopisz klastry zdalne** do `values-single.yaml`. Nazwy są dowolne; tak będą widoczne w konsoli:

```yaml
agents:
  - name: klaster-b
  - name: klaster-c
```

**3. Zaktualizuj konsolę** (kubectl ustawiony na klaster konsoli):

```sh
helm upgrade k8s-console ./k8s-console -n k8s-console -f values-single.yaml
```

Na końcu wyniku (sekcja NOTES) jest dla każdego klastra jedno polecenie zaczynające się od
`kubectl -n k8s-console get secret …`. Wynik można zobaczyć ponownie: `helm status k8s-console -n k8s-console`.

**4. Uruchom to polecenie** (nadal na klastrze konsoli). Nic nie zmienia — tylko wypisuje jedną linię
`helm install k8s-console-agent …` z adresem konsoli, nazwą klastra i kluczem agenta. Klucz jest hasłem
agenta: nie zapisuj go w repozytorium.

**5. Przełącz kubectl na klaster zdalny** (jak zwykle się do niego łączysz) i w katalogu, w którym
leży `k8s-console/`, wklej wypisaną linię. Linia zakłada rozpakowany chart w katalogu `k8s-console`;
jeśli masz tylko plik `.tgz`, zamień w niej `./k8s-console` na nazwę pliku (np. `k8s-console-0.2.0.tgz`). Jeśli obraz idzie przez Artifactory z logowaniem, Secret do
rejestru musi istnieć także w namespace `k8s-console` na klastrze zdalnym.

**6. Sprawdź** stronę startową konsoli: kafel klastra pokazuje „przez agenta · połączony …”. Gdy jest
„agent rozłączony”, przyczyna jest w logu agenta (na klastrze zdalnym):

```sh
kubectl -n k8s-console logs deploy/k8s-console-agent
```

| W logu agenta | Co zrobić |
|---|---|
| `konsola nie zna tego klastra albo klucz agenta jest inny` | klaster nie jest w `agents` konsoli albo wklejony klucz jest z innej instalacji — powtórz kroki 3–5 |
| `certificate signed by unknown authority` (z podpowiedzią o CA) | certyfikat Ingressu konsoli jest od CA organizacji — dopisz `--set-file trust.caBundle=ca.pem` do polecenia agenta |
| `no such host`, `connection refused`, `timeout` | klaster zdalny nie ma drogi do adresu konsoli (DNS, firewall); przez proxy: `extraEnv` z `HTTPS_PROXY` |
| `pod tym adresem nie ma konsoli z obsługą agentów` | zły `agent.server` albo konsola w starej wersji |

Gdy konsola i agent są w różnych wersjach, kafel pokazuje „inna wersja agenta”: zainstaluj agenta
w wersji konsoli (`helm upgrade k8s-console-agent …` z tym samym chartem).

### Prometheus i Hubble klastra zdalnego (opcjonalnie)

Dopisz do linii z kroku 5:

- Prometheus (rekomendacje z historii, ruch Istio, zajętość wolumenów):
  `--set agent.prometheus.url=http://<usługa>.<namespace>.svc:<port>`. Z hasłem: najpierw na klastrze
  zdalnym `kubectl -n k8s-console create secret generic prometheus-haslo --from-literal=password=<hasło>`,
  potem `--set agent.prometheus.username=<użytkownik> --set agent.prometheus.passwordSecret.name=prometheus-haslo`.
- Hubble (strona Ruch, Cilium): `--set agent.hubble.address=hubble-relay.kube-system.svc:80`.
  Relay z TLS (Cilium `hubble.relay.tls.server.enabled`): przekopiuj certyfikat klienta Hubble do
  Secretu w namespace `k8s-console` (klucze `ca.crt`, `tls.crt`, `tls.key`) i dopisz
  `--set agent.hubble.address=hubble-relay.kube-system.svc:443 --set agent.hubble.tls.enabled=true
  --set agent.hubble.tls.secretName=<secret> --set agent.hubble.tls.serverName=agent.hubble-relay.cilium.io`.

Konsola pokazuje te strony dla klastra dopiero wtedy, gdy agent zgłosi, że ma dane źródło.

### Dodanie i usunięcie klastra

Nowy klaster: dopisz go do `agents` i powtórz kroki 3–6. Usunięcie klastra z `agents` i `helm upgrade`
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
- Połączenie agenta przechodzi przez Ingress jak WebSocket (nagłówek `Upgrade`). Agent i konsola co
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
