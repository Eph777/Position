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
DB_PORT = int(os.environ.get("DB_PORT", "5432"))

# Initialize connection pool
try:
    postgresql_pool = psycopg2.pool.SimpleConnectionPool(
        1, 20,
        host=DB_HOST,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        port=DB_PORT
    )
    if postgresql_pool:
        print("PostgreSQL connection pool created successfully")
except (Exception, psycopg2.DatabaseError) as error:
    print(f"Error while connecting to PostgreSQL: {error}")

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
        conn = postgresql_pool.getconn()
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
        if conn:
            postgresql_pool.putconn(conn)

@app.route('/logout', methods=['POST'])
def logout_player():
    """
    Archives player traces when they leave the game.
    Moves data from player_traces -> player_traces_archive
    """
    data = request.json
    if not data or 'player' not in data:
        return jsonify({"error": "Invalid data format"}), 400

    player = data['player']
    
    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        # 1. Copy to archive
        archive_query = """
            INSERT INTO player_traces_archive (player_name, x, y, z, timestamp)
            SELECT player_name, x, y, z, timestamp
            FROM player_traces
            WHERE player_name = %s
        """
        cursor.execute(archive_query, (player,))
        
        # 2. Delete from active
        delete_query = """
            DELETE FROM player_traces
            WHERE player_name = %s
        """
        cursor.execute(delete_query, (player,))
        
        conn.commit()
        cursor.close()
        print(f"Archived session for player: {player}")
        return jsonify({"status": "archived"}), 200
        
    except (Exception, psycopg2.DatabaseError) as error:
        if conn:
            conn.rollback()
        print(f"Error archiving trace: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn:
            postgresql_pool.putconn(conn)

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
        conn = postgresql_pool.getconn()
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
    except (Exception, psycopg2.DatabaseError) as error:
        print(f"Error retrieving traces: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn:
            postgresql_pool.putconn(conn)

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({"status": "running"}), 200

if __name__ == '__main__':
    # Run the server on port 5000
    app.run(host='0.0.0.0', port=5000)
