# ACEest Fitness & Gym — Assignment 2 Report

## CI/CD architecture overview

This project reuses the Flask fitness-management application developed for
Assignment 1. The source and infrastructure are version-controlled in GitHub.
GitHub Actions runs on pushes to `main` and `dev` and on pull requests targeting
`main`. The workflow installs the pinned Python dependencies, runs Flake8 and
Pytest with coverage, publishes JUnit/coverage artifacts, builds the Docker
image, and runs the test suite inside the image.

The Jenkins pipeline polls the configured Git repository every five minutes.
Each build creates a versioned Docker image tagged with the Jenkins build number
and short commit SHA. It runs lint and tests inside that image, publishes the
JUnit and coverage reports, submits the coverage data for SonarQube analysis,
and waits for the configured quality gate. On `main`, a successful build
publishes the versioned image and `latest` tag to Docker Hub, then uses the
Jenkins `DEPLOYMENT_STRATEGY` parameter to deploy to Kubernetes. Jenkins checks
rollout readiness and the `/readyz` endpoint; when the rollout or smoke check
fails, it requests a Kubernetes rollback or disables candidate traffic.

Kubernetes deployment resources are kept under `k8s/`. The default Deployment
uses two replicas, Kubernetes rolling updates with `maxUnavailable: 0`,
readiness and liveness probes, resource requests/limits, and a persistent
volume claim for the SQLite database. A NodePort Service exposes the dashboard
and API on a local Minikube cluster. Alternative manifests demonstrate
blue-green service switching, weighted canary routing, header-based A/B
routing, and NGINX request mirroring for shadow traffic. The rollback helpers
restore the prior blue/green slot or disable candidate traffic.

## Challenges and mitigation strategies

**Coordinating checks and deployment:** Publishing an image or deploying before
tests and quality checks finish could expose a faulty build. The Jenkins
pipeline orders the stages so image publication and Kubernetes deployment
occur only after lint, container tests, and the SonarQube quality gate pass.
Images are tagged by build and commit instead of relying only on `latest`.

**Deployment health and recovery:** A process can start but still fail to serve
requests. The application now exposes `/readyz`, which verifies database
connectivity. Kubernetes uses this endpoint for readiness checks, and Jenkins
checks it after rollout. Failed rollouts are reverted using Kubernetes rollout
history; blue-green promotion also records the previously active slot.

**Different deployment strategies:** Canary, A/B, shadow, and blue-green
deployments use different traffic-selection mechanisms. Separate manifests
make these strategies explicit and avoid enabling incompatible Ingress rules
at the same time. Shadow requests use an isolated ephemeral database so
mirrored writes do not affect the stable application data.

**Local versus production persistence:** SQLite is suitable for the existing
assignment application and local single-node demonstration, but a shared
SQLite file is not an appropriate multi-node production database. The sample
uses a PVC for local persistence and documents that a managed database should
replace SQLite before multi-node production scaling.

**External service credentials:** Docker Hub, SonarQube, and Kubernetes access
are environment-specific and must not be stored in source control. The Jenkins
pipeline refers to Jenkins credentials by ID, and the repository contains no
tokens, kubeconfig files, or passwords. Jenkins must be configured with
`dockerhub-credentials`, `kuberconfig`, and a SonarQube server/scanner before
the publish and deployment stages can run.

## Key automation outcomes

- Automated linting and unit tests are configured in GitHub Actions and
  Jenkins, including tests inside the built container.
- JUnit and coverage reports are produced for CI runs, and coverage is passed
  to SonarQube for quality-gate evaluation.
- The Jenkins pipeline can publish immutable build-specific Docker Hub tags and
  deploy to Kubernetes after successful validation.
- Kubernetes manifests define health-checked rolling updates, a persistent
  volume, NodePort access, and example progressive-delivery patterns.
- Rollback procedures are documented and implemented for rolling, blue-green,
  canary, A/B, and shadow traffic.

## Evidence to complete before submission

Replace the entries below with evidence from your own configured services.
These values cannot be generated until Jenkins, Docker Hub, SonarQube, and the
target cluster are configured and reachable.

| Evidence | Value |
| --- | --- |
| GitHub repository URL | `<public repository URL>` |
| Jenkins successful build | `<build number and URL>` |
| SonarQube quality-gate result | `<project dashboard URL or screenshot>` |
| Docker Hub image repository and version tag | `<repository URL and tag>` |
| Kubernetes deployment endpoint | Local Minikube only; run `kubectl port-forward -n aceest service/aceest-fitness 5000:80` and use `http://localhost:5000/`. Verified locally; not a public submission endpoint. |
| Demonstrated rollback/progressive strategy | `<strategy and run evidence>` |
