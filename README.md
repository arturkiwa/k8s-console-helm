# K8s Console — instalacja (Helm)

Konsola webowa do Kubernetesa. Instalujesz ją na klastrze jednym poleceniem `helm install`. Widzi ten
klaster, na którym działa. Każdy użytkownik konsoli ma takie uprawnienia, jakie nadaje mu RBAC klastra,
a uprawnienia zakłada Helm.

Obraz: `docker.io/arturkiwa/k8s-console:0.2.0`.

## Co pobrać

Z zakładki **Releases** (wersja `v0.2.0`) dwa pliki:

- `k8s-console-0.2.0.tgz` — chart Helm,
- `values-single.yaml` — ustawienia: użytkownicy i hasła.

Oba pliki przenieś na maszynę, z której masz `kubectl` i `helm` do klastra.

## 1. Hasła

Konsola ma dwóch użytkowników: `viewer` (tylko podgląd) i `operator` (podgląd i akcje). Hasła wymyślasz
sam. W pliku nie zapisuje się hasła wprost, tylko jego hash, czyli zaszyfrowaną postać.

Hash zrobisz jednym z poleceń (wpisz hasło, wynik zaczyna się od `$2`):

```sh
htpasswd -nbBC 10 "" 'TwojeHaslo' | tr -d ':\n'; echo     # pakiet httpd-tools / apache2-utils
docker run --rm -i docker.io/arturkiwa/k8s-console:0.2.0 hash-password   # albo tak, jeśli masz dockera
```

Wklej hashe do `values-single.yaml` w miejsca `WKLEJ-HASH`. Do logowania używasz hasła, nie hasha.

## 2. Instalacja

Na klastrze, do którego jesteś podłączony (ten, który pokazuje `kubectl get nodes`), potrzebne są
uprawnienia cluster-admin.

```sh
helm install k8s-console k8s-console-0.2.0.tgz -n k8s-console --create-namespace -f values-single.yaml
kubectl -n k8s-console rollout status deploy/k8s-console
```

Na kolejnym klastrze przełącz się tak, jak zwykle, i powtórz to samo.

## 3. Otwarcie konsoli

Na maszynie z `kubectl`:

```sh
kubectl -n k8s-console port-forward --address 0.0.0.0 svc/k8s-console 8080:80
```

W przeglądarce otwórz `http://<adres tej maszyny>:8080` i zaloguj się jako `viewer` albo `operator`.

- Bez `--address 0.0.0.0` konsola jest dostępna tylko z tej samej maszyny (`http://localhost:8080`).
- Port 8080 musi być otwarty na tej maszynie dla Twojej przeglądarki. Jeśli nie jest, użyj tunelu SSH
  z komputera z przeglądarką: `ssh -L 8080:127.0.0.1:8080 <maszyna>` i otwórz `http://localhost:8080`.
- Forward kończy się przy restarcie poda konsoli. Wtedy uruchom go ponownie.

## Ustawienia

- Konsola domyślnie **tylko czyta**. Akcje operatora (restart, skalowanie, cordon) włączysz, dodając do
  `helm install` opcję `--set localCluster.allowMutations=true`.
- Nazwa klastra w konsoli: `--set localCluster.name=<nazwa>`.

## Obraz przez Artifactory

Gdy klaster pobiera obrazy przez Artifactory (proxy Docker Hub), w `values-single.yaml` zmień adres
obrazu na adres w Artifactory, np.:

```yaml
image:
  repository: artifactory.example.internal/docker-remote/arturkiwa/k8s-console
  tag: "0.2.0"
```

Dokładny adres zależy od konfiguracji Artifactory (nazwa repozytorium zdalnego). Najłatwiej sprawdzić go
tak, jak dla innych obrazów z Docker Hub pobieranych w Twoim środowisku: zamiast `docker.io/` jest
prefiks Artifactory, a reszta (`arturkiwa/k8s-console`) zostaje.

Jeśli Artifactory wymaga logowania przy pobieraniu, **przed** `helm install` utwórz Secret z danymi
do Artifactory:

```sh
kubectl create namespace k8s-console
kubectl -n k8s-console create secret docker-registry artifactory \
  --docker-server=artifactory.example.internal \
  --docker-username=<użytkownik> --docker-password=<hasło lub token>
```

i w `values-single.yaml` ustaw:

```yaml
imagePullSecrets:
  - name: artifactory
```

Jeśli pod konsoli wisi w `ImagePullBackOff`, przyczynę pokaże
`kubectl -n k8s-console describe pod -l app.kubernetes.io/name=k8s-console` (sekcja Events na dole).

## Kilka klastrów w jednej konsoli

Zamiast konsoli na każdym klastrze: konsola na jednym klastrze, a na pozostałych mały **agent** z tego
samego chartu. Agent sam łączy się do konsoli, więc na klastrach zdalnych nic nie trzeba wystawiać.
Konsola potrzebuje wtedy adresu (Ingress), do którego agenty mają dostęp. Instrukcja krok po kroku:
[k8s-console/README.md](k8s-console/README.md), sekcja „Jedna konsola, kilka klastrów (agent)”.

## Usunięcie

```sh
helm uninstall k8s-console -n k8s-console
kubectl delete namespace k8s-console
```
