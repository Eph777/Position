import os
import datetime
from flask import Flask, request, jsonify
import mysql.connector
from mysql.connector import pooling, Error

app = Flask(__name__)

# Database configuration - Update these with your actual credentials
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "luanti_db")
DB_USER = os.environ.get("DB_USER", "luanti")
DB_PASS = os.environ.get("DB_PASS", "password")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))

# Initialize connection pool
try:
    mysql_pool = mysql.connector.pooling.MySQLConnectionPool(
        pool_name="luanti_pool",
        pool_size=20,
        pool_reset_session=True,
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        port=DB_PORT
    )
    print("MySQL connection pool created successfully")
except Error as error:
    print(f"Error while connecting to MySQL: {error}")

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
        conn = mysql_pool.get_connection()
        cursor = conn.cursor()
        query = """
            INSERT INTO player_traces (player_name, x, y, z)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(query, (player, x, y, z))
        conn.commit()
        cursor.close()
        return jsonify({"status": "success"}), 201
    except Error as error:
        if conn:
            conn.rollback()
        print(f"Error saving trace: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()

@app.route('/traces', methods=['GET'])
def get_traces():
    """
    Retrieves player traces from the database.
    Optional query parameters:
    - player: filter by player name
    - limit: number of records to return (default: 100)
    """
    player_name = request.args.get('player')
    limit = request.args.get('limit', 100, type=int)
    
    conn = None
    try:
        conn = mysql.connector.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
            port=DB_PORT
        )
        cursor = conn.cursor()
        
        if player_name:
            query = """
                SELECT id, player_name, x, y, z, timestamp
                FROM player_traces
                WHERE player_name = %s
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (player_name, limit))
        else:
            query = """
                SELECT id, player_name, x, y, z, timestamp
                FROM player_traces
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (limit,))
        
        rows = cursor.fetchall()
        cursor.close()
        
        # Convert to list of dictionaries
        traces = []
        for row in rows:
            traces.append({
                "id": row[0],
                "player_name": row[1],
                "x": row[2],
                "y": row[3],
                "z": row[4],
                "timestamp": row[5].isoformat() if row[5] else None
            })
        
        return jsonify({"count": len(traces), "traces": traces}), 200
    except Error as error:
        print(f"Error retrieving traces: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn and conn.is_connected():
            conn.close()

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({"status": "running"}), 200

if __name__ == '__main__':
    # Run the server on port 5000
    app.run(host='0.0.0.0', port=5000)
