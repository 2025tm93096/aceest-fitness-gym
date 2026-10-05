# ACEest Fitness & Gym — Automated CI/CD Platform

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

The API is available at `http://localhost:5000`. The application creates the
SQLite database automatically on startup. By default it uses
`aceest_fitness.db`; set `ACEEST_DB` to use another path:

```bash
ACEEST_DB=/path/to/aceest_fitness.db python -m app.app
```

For production-style local serving, use Gunicorn:

```bash
gunicorn --bind 0.0.0.0:5000 --workers 2 app.app:app
```

## 2. API Reference

All endpoints return JSON.

| Method | Endpoint | Description |
| --- | --- | --- |
| `GET` | `/` | Health check |
| `GET` | `/api/v1/programs` | List available fitness programs |
| `GET` | `/api/v1/clients` | List all clients |
| `POST` | `/api/v1/clients` | Create a client |
| `GET` | `/api/v1/clients/<name>` | Get one client by name |
| `POST` | `/api/v1/clients/<name>/progress` | Log adherence progress |
| `POST` | `/api/v1/clients/<name>/workouts` | Log a workout |

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
pytest tests/ -v
flake8 app/ tests/ --max-line-length=120
```

## 4. Docker

Build and run the production-style container:

```bash
docker build -t aceest-fitness-app .
docker run --rm -p 5000:5000 aceest-fitness-app
```

The container listens on port `5000` and runs Gunicorn with two workers. To
persist the SQLite database outside the container, mount a directory and set
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
targeting `main`. It installs dependencies, runs Flake8, builds the Docker
image, and runs Pytest inside the image.

Jenkins follows the same flow through the `Jenkinsfile`: checkout, lint,
Docker build, and in-container regression tests. Jenkins requires Python 3,
Docker, and permission to run Docker commands on the build agent.

## 6. Project Structure

```text
app/app.py              Flask application and SQLite persistence
tests/                  Pytest test suite and fixtures
Dockerfile              Multi-stage production container build
Jenkinsfile             Jenkins CI pipeline
.github/workflows/      GitHub Actions CI/CD workflow
requirements.txt        Python runtime and development dependencies
```