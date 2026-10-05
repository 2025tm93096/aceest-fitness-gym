import os
import sqlite3
from datetime import datetime
from flask import Flask, jsonify, request

app = Flask(__name__)
DB_NAME = os.environ.get("ACEEST_DB", "aceest_fitness.db")

PROGRAMS_CONFIG = {
    "Fat Loss (FL)": {"factor": 22, "desc": "3-day full-body fat loss circuit"},
    "Muscle Gain (MG)": {"factor": 35, "desc": "Push/Pull/Legs hypertrophy split"},
    "Beginner (BG)": {"factor": 26, "desc": "Full body technique & consistency"}
}


def get_db_connection():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            age INTEGER,
            height REAL,
            weight REAL,
            program TEXT NOT NULL,
            calories INTEGER,
            target_weight REAL,
            membership_status TEXT DEFAULT 'Active'
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_name TEXT NOT NULL,
            week TEXT NOT NULL,
            adherence INTEGER NOT NULL
        )
    """)
    cur.execute("""
        CREATE TABLE IF NOT EXISTS workouts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            client_name TEXT NOT NULL,
            workout_type TEXT NOT NULL,
            duration_min INTEGER NOT NULL,
            notes TEXT
        )
    """)
    conn.commit()
    conn.close()


init_db()


@app.route("/", methods=["GET"])
def health_check():
    return jsonify({
        "status": "UP",
        "service": "ACEest Fitness & Performance API",
        "version": "1.0.0"
    }), 200


@app.route("/api/v1/programs", methods=["GET"])
def get_programs():
    return jsonify({"programs": PROGRAMS_CONFIG}), 200


@app.route("/api/v1/clients", methods=["GET", "POST"])
def handle_clients():
    conn = get_db_connection()
    cur = conn.cursor()

    if request.method == "POST":
        data = request.get_json() or {}
        name = data.get("name")
        program = data.get("program")

        if not name or not program:
            conn.close()
            return jsonify({"error": "name and program are required"}), 400

        if program not in PROGRAMS_CONFIG:
            conn.close()
            return jsonify({"error": f"Invalid program. Choose from: {list(PROGRAMS_CONFIG.keys())}"}), 400

        age = data.get("age", 0)
        height = data.get("height", 0.0)
        weight = float(data.get("weight", 0.0))
        target_weight = data.get("target_weight", 0.0)

        factor = PROGRAMS_CONFIG[program]["factor"]
        calories = int(weight * factor) if weight > 0 else 0

        try:
            cur.execute("""
                INSERT INTO clients (name, age, height, weight, program, calories, target_weight)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (name.strip(), age, height, weight, program, calories, target_weight))
            conn.commit()
            client_id = cur.lastrowid
            conn.close()
            return jsonify({
                "message": "Client created successfully",
                "client": {
                    "id": client_id,
                    "name": name,
                    "program": program,
                    "calories": calories,
                    "weight": weight
                }
            }), 201
        except sqlite3.IntegrityError:
            conn.close()
            return jsonify({"error": "Client with this name already exists"}), 409

    cur.execute("SELECT * FROM clients")
    rows = cur.fetchall()
    clients = [dict(row) for row in rows]
    conn.close()
    return jsonify({"clients": clients, "count": len(clients)}), 200


@app.route("/api/v1/clients/<name>", methods=["GET"])
def get_client(name):
    conn = get_db_connection()
    cur = conn.cursor()
    cur.execute("SELECT * FROM clients WHERE name=?", (name.strip(),))
    row = cur.fetchone()
    conn.close()

    if not row:
        return jsonify({"error": "Client not found"}), 404

    return jsonify({"client": dict(row)}), 200


@app.route("/api/v1/clients/<name>/progress", methods=["POST"])
def log_progress(name):
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT id FROM clients WHERE name=?", (name.strip(),))
    if not cur.fetchone():
        conn.close()
        return jsonify({"error": "Client not found"}), 404

    data = request.get_json() or {}
    adherence = data.get("adherence")
    if adherence is None or not (0 <= adherence <= 100):
        conn.close()
        return jsonify({"error": "Valid adherence percentage (0-100) required"}), 400

    week = data.get("week", datetime.now().strftime("Week %U - %Y"))
    cur.execute("""
        INSERT INTO progress (client_name, week, adherence)
        VALUES (?, ?, ?)
    """, (name.strip(), week, adherence))
    conn.commit()
    conn.close()

    return jsonify({"message": "Progress logged successfully", "week": week, "adherence": adherence}), 201


@app.route("/api/v1/clients/<name>/workouts", methods=["POST"])
def log_workout(name):
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT id FROM clients WHERE name=?", (name.strip(),))
    if not cur.fetchone():
        conn.close()
        return jsonify({"error": "Client not found"}), 404

    data = request.get_json() or {}
    workout_type = data.get("workout_type")
    duration = data.get("duration_min", 60)
    notes = data.get("notes", "")

    if not workout_type:
        conn.close()
        return jsonify({"error": "workout_type is required"}), 400

    cur.execute("""
        INSERT INTO workouts (client_name, workout_type, duration_min, notes)
        VALUES (?, ?, ?, ?)
    """, (name.strip(), workout_type, duration, notes))
    conn.commit()
    conn.close()

    return jsonify({"message": "Workout logged", "type": workout_type, "duration_min": duration}), 201


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
