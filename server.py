import os
import datetime
from flask import Flask, request, jsonify
import psycopg2
from psycopg2 import pool

app = Flask(__name__)

# Database configuration - Update these with your actual credentials
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "luanti_db")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "password")

# Initialize connection pool
try:
    postgreSQL_pool = psycopg2.pool.SimpleConnectionPool(
        1, 20,
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS
    )
    if postgreSQL_pool:
        print("Connection pool created successfully")
except (Exception, psycopg2.DatabaseError) as error:
    print("Error while connecting to PostgreSQL", error)

@app.route('/position', methods=['POST'])
def log_position():
    """
    Receives position data from Luanti mod.
    Expected JSON: {"player": "name", "pos": {"x": 1.0, "y": 2.0, "z": 3.0}}
    """
    data = request.json
    if not data or 'player' not in data or 'pos' not in data:
        return jsonify({"error": "Invalid data format"}), 400

    player = data['player']
    pos = data['pos']
    x = pos.get('x', 0)
    y = pos.get('y', 0)
    z = pos.get('z', 0)
    
    # Insert into database
    conn = None
    try:
        conn = postgreSQL_pool.getconn()
        cursor = conn.cursor()
        query = """
            INSERT INTO player_traces (player_name, x, y, z)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(query, (player, x, y, z))
        conn.commit()
        cursor.close()
        return jsonify({"status": "success"}), 201
    except (Exception, psycopg2.DatabaseError) as error:
        if conn:
            conn.rollback()
        print(f"Error saving trace: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn:
            postgreSQL_pool.putconn(conn)

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({"status": "running"}), 200

if __name__ == '__main__':
    # Run the server on port 5000
    app.run(host='0.0.0.0', port=5000)
