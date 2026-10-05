import json


def test_health_check(client):
    res = client.get("/")
    assert res.status_code == 200
    data = json.loads(res.data)
    assert data["status"] == "UP"


def test_get_programs(client):
    res = client.get("/api/v1/programs")
    assert res.status_code == 200
    data = json.loads(res.data)
    assert "Fat Loss (FL)" in data["programs"]


def test_create_client_success(client):
    payload = {
        "name": "Karthik Raj",
        "age": 28,
        "height": 178,
        "weight": 80.0,
        "program": "Muscle Gain (MG)"
    }
    res = client.post("/api/v1/clients", json=payload)
    assert res.status_code == 201
    data = json.loads(res.data)
    assert data["client"]["calories"] == 2800


def test_create_client_missing_fields(client):
    res = client.post("/api/v1/clients", json={"age": 25})
    assert res.status_code == 400


def test_log_progress_success(client):
    client.post("/api/v1/clients", json={"name": "Vikram", "program": "Beginner (BG)", "weight": 70})
    res = client.post("/api/v1/clients/Vikram/progress", json={"adherence": 85})
    assert res.status_code == 201
    data = json.loads(res.data)
    assert data["adherence"] == 85


def test_log_workout_success(client):
    client.post("/api/v1/clients", json={"name": "Ananya", "program": "Fat Loss (FL)", "weight": 65})
    res = client.post("/api/v1/clients/Ananya/workouts", json={
        "workout_type": "Conditioning",
        "duration_min": 45,
        "notes": "Assault Bike + Kettlebell swings"
    })
    assert res.status_code == 201
    data = json.loads(res.data)
    assert data["type"] == "Conditioning"
