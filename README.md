# Aceest Fitness & Gym — Automated CI/CD Platform

Production-ready backend API service for gym operations, containerized with Docker and verified via GitHub Actions and Jenkins automated pipelines.

---

## 1. Quickstart & Local Setup

### Prerequisites
- Python 3.11+
- Docker Engine 24+

### Setup Virtual Environment
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run Locally
```bash
python -m app.app
```

The Flask dashboard is available at `http://localhost:5000/dashboard`. The API
health endpoint is available at `http://localhost:5000/`. The application creates the
SQLite database automatically on startup. By default it uses
`aceest_fitness.db`; set `ACEEST_DB` to use another path:

```bash
ACEEST_DB=/path/to/aceest_fitness.db python -m app.app
```

For production-style local serving, use Gunicorn:

```bash
gunicorn --bind 0.0.0.0:5000 --workers 2 app.app:app
```

## 2. Frontend and API

The Flask frontend is rendered from `app/templates/index.html` and uses the API
to load clients and programs, create clients, log adherence progress, and log
workouts. Open the dashboard at:

```text
http://localhost:5000/dashboard
```

### API Reference

API endpoints return JSON.

| Method | Endpoint | Description |
| --- | --- | --- |
| `GET` | `/` | Health check |
| `GET` | `/api/v1/programs` | List available fitness programs |
| `GET` | `/api/v1/clients` | List all clients |
| `POST` | `/api/v1/clients` | Create a client |
| `GET` | `/api/v1/clients/<name>` | Get one client by name |
| `POST` | `/api/v1/clients/<name>/progress` | Log adherence progress |
| `POST` | `/api/v1/clients/<name>/workouts` | Log a workout |

The dashboard route returns the HTML frontend rather than JSON.

### Create a Client

`name` and `program` are required. Valid programs are `Fat Loss (FL)`,
`Muscle Gain (MG)`, and `Beginner (BG)`. Calories are calculated from weight
and the selected program.

```bash
curl -X POST http://localhost:5000/api/v1/clients \
	-H 'Content-Type: application/json' \
	-d '{"name":"Karthik Raj","age":28,"height":178,"weight":80,"program":"Muscle Gain (MG)","target_weight":85}'
```

### Log Progress

`adherence` must be a percentage from 0 to 100. `week` is optional and
defaults to the current week.

```bash
curl -X POST http://localhost:5000/api/v1/clients/Karthik%20Raj/progress \
	-H 'Content-Type: application/json' \
	-d '{"adherence":85,"week":"Week 12 - 2026"}'
```

### Log a Workout

`workout_type` is required. `duration_min` defaults to 60 minutes and
`notes` is optional.

```bash
curl -X POST http://localhost:5000/api/v1/clients/Karthik%20Raj/workouts \
	-H 'Content-Type: application/json' \
	-d '{"workout_type":"Strength","duration_min":45,"notes":"Upper body"}'
```

## 3. Testing and Code Quality

Run the automated tests and lint checks locally:

```bash
python -m pytest tests/ -v
flake8 app/ tests/ --max-line-length=120
```

The test suite includes API behavior and dashboard delivery tests. Use
`./venv/bin/python -m pytest tests/ -v` when the virtual environment is not
activated.

## 4. Docker

Build and run the production-style container:

```bash
docker build -t aceest-fitness-app .
docker run --rm -p 5000:5000 aceest-fitness-app
```

The container listens on port `5000` and runs Gunicorn with two workers. To
open the frontend after starting the container, visit
`http://localhost:5000/dashboard`. To persist the SQLite database outside the
container, mount a directory and set
`ACEEST_DB` to a file in that directory:

```bash
mkdir -p data
docker run --rm -p 5000:5000 \
	-e ACEEST_DB=/data/aceest_fitness.db \
	-v "$(pwd)/data:/data" \
	aceest-fitness-app
```

The image also contains the test suite, so its tests can be run in the same
environment used by CI:

```bash
docker run --rm aceest-fitness-app pytest tests/ -v
```

## 5. CI/CD

GitHub Actions runs on pushes to `main` and `dev`, and on pull requests
targeting `main`. It runs Flake8 and Pytest with coverage, publishes JUnit and
coverage reports as workflow artifacts, then builds the Docker image and runs
the tests inside it.

Use `main` for stable releases and feature branches or `dev` for work in
progress. Tag release commits with semantic versions, for example:

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The `Jenkinsfile` polls Git every five minutes and runs containerized lint and
tests, SonarQube analysis with a quality gate, Docker Hub image publishing, and
a selectable Kubernetes deployment strategy on `main`. Choose rolling,
blue-green, canary, A/B, or shadow from the Jenkins `DEPLOYMENT_STRATEGY`
parameter. Image tags include the Jenkins build number and short Git commit
SHA.

Configure Jenkins with the Pipeline, Git, Credentials Binding, SonarQube
Scanner, JUnit, and Workspace Cleanup plugins. Add:

- A username/password credential named `dockerhub-credentials` (use a Docker
  Hub access token as the password).
- A secret-file credential named `kubeconfig` for a cluster reachable by the
  Jenkins agent.
- A SonarQube server named `SonarQube` and scanner tool named `SonarScanner`.
  Configure the SonarQube webhook to call
  `https://<jenkins-url>/sonarqube-webhook/`.
- Docker, kubectl, and curl on the Jenkins agent, with permission to access
  Docker and the Kubernetes cluster.

The pipeline defaults to the Docker Hub repository
`2025tm93096/aceest-fitness-app`; change the Jenkins `DOCKERHUB_REPO` parameter
if you publish under another account.

## 6. Kubernetes deployment

The default manifests target a local Minikube cluster and use a persistent
volume for the SQLite database. Start the cluster and apply the rolling-update
configuration:

```bash
minikube start --driver=docker
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storage.yaml
kubectl apply -f k8s/service.yaml
sed 's|IMAGE_PLACEHOLDER|2025tm93096/aceest-fitness-app:v1.0.0|g' \
  k8s/deployment.yaml | kubectl apply -f -
kubectl rollout status deployment/aceest-fitness -n aceest
```

Push the referenced image to Docker Hub first. For access from macOS with Minikube's Docker driver, forward the Service to a
local port:

```bash
kubectl port-forward -n aceest service/aceest-fitness 5000:80
```

While that command is running, open `http://localhost:5000/` or
`http://localhost:5000/dashboard`. The NodePort is `30084`; use
`minikube service aceest-fitness -n aceest --url` on platforms where the
Minikube node IP is reachable from the host.

For private Docker Hub repositories, configure an `imagePullSecret` in the
`aceest` namespace and reference it from the Deployment pod specification.

The deployment uses two replicas, readiness/liveness probes, resource limits,
and Kubernetes rolling updates (`maxUnavailable: 0`). To roll back a failed
or unhealthy update:

```bash
sh k8s/rollback.sh rolling
```

### Progressive delivery strategies

The Jenkins `DEPLOYMENT_STRATEGY` parameter invokes `k8s/deploy.sh` to
configure the selected strategy. The supporting manifests under
`k8s/strategies/` can also be applied manually. Blue-green promotion waits for
the candidate deployment to be ready before switching the Service; the
previous slot is recorded so it can be restored:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/storage.yaml
sed 's|IMAGE_PLACEHOLDER|2025tm93096/aceest-fitness-app:v1.0.0|g' \
  k8s/strategies/blue-green.yaml | kubectl apply -f -
kubectl set image deployment/aceest-green \
  app=2025tm93096/aceest-fitness-app:v1.0.1 -n aceest
sh k8s/promote-blue-green.sh green
sh k8s/rollback.sh blue-green
```

For canary and A/B routing, enable the Minikube NGINX Ingress add-on and apply
the candidate workload with the desired image. Apply
`k8s/ingress/stable.yaml`, then choose **one** of
`k8s/strategies/canary-ingress.yaml` (10% canary traffic) or
`k8s/strategies/ab-test.yaml` (requests with
`X-Aceest-Experiment: variant-b` go to the candidate). These are alternative
Ingress rules and should not be active together. Use
`sh k8s/rollback.sh canary` or `sh k8s/rollback.sh ab` to stop candidate
traffic.

For shadow traffic, deploy `k8s/strategies/shadow.yaml`, replace the stable
Ingress with `k8s/strategies/shadow-ingress.yaml`, and monitor the shadow
deployment separately. Shadow requests use an isolated ephemeral database so
mirrored write requests cannot alter production data. Disable mirroring with
`sh k8s/rollback.sh shadow`.

Render the candidate manifests with the intended image tag before applying
them, for example:

```bash
sed 's|IMAGE_PLACEHOLDER|2025tm93096/aceest-fitness-app:v1.0.1|g' \
  k8s/strategies/canary.yaml | kubectl apply -f -
sed 's|IMAGE_PLACEHOLDER|2025tm93096/aceest-fitness-app:v1.0.1|g' \
  k8s/strategies/shadow.yaml | kubectl apply -f -
```

The sample uses SQLite on a single-node/local cluster. For multi-node or
production cloud deployment, move persistence to a managed database before
scaling or using concurrent traffic strategies; a shared SQLite file is not a
production database design. Ingress examples require an NGINX Ingress
controller.

## 7. Project Structure

```text
app/app.py              Flask application, API routes, and SQLite persistence
app/templates/index.html Flask-rendered frontend dashboard
tests/                  Pytest test suite and fixtures
Dockerfile              Multi-stage production container build
Jenkinsfile             Jenkins CI pipeline
.github/workflows/      GitHub Actions CI/CD workflow
k8s/                    Kubernetes deployment and strategy manifests
k8s/rollback.sh         Rollback helper for supported strategies
docs/                   Assignment 2 report and evidence checklist
requirements.txt        Python runtime and development dependencies
```