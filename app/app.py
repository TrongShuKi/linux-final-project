import os
from flask import Flask, request, jsonify
import psycopg2

app = Flask(__name__)

def get_conn():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "127.0.0.1"),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_NAME", "appdb"),
        user=os.environ.get("DB_USER", "appuser"),
        password=os.environ.get("DB_PASSWORD"),
    )

@app.get("/health")
def health():
    return jsonify(status="ok")

@app.get("/items")
def list_items():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id, name FROM items;")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return jsonify([{"id": r[0], "name": r[1]} for r in rows])

@app.post("/items")
def add_item():
    data = request.get_json()
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO items (name) VALUES (%s) RETURNING id;", (data["name"],))
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close(); conn.close()
    return jsonify(id=new_id), 201

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", 8000)))
