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
    Expected JSON: {"player": "name", "world": "worldname", "pos": {"x": 1.0, "y": 2.0, "z": 3.0}}
    """
    data = request.json
    if not data or 'player' not in data or 'pos' not in data:
        return jsonify({"error": "Invalid data format"}), 400

    player = data['player']
    world = data.get('world', 'default')  # Default world if not specified
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
            INSERT INTO player_traces (player_name, world_name, x, y, z)
            VALUES (%s, %s, %s, %s, %s)
        """
        cursor.execute(query, (player, world, x, y, z))
        conn.commit()
        
        # 3. Success response immediately (don't let cleanup block this)
        response = jsonify({"status": "success"})
        status_code = 201
        
        # 4. Cleanup (Best Effort)
        try:
            # We use a new cursor check for cleanup to isolate it
            cursor.close()
            cursor = conn.cursor()
            
            # Lazy Cleanup: Archive "stale" records (older than 60s)
            cleanup_query = """
                WITH moved_rows AS (
                    INSERT INTO player_traces_archive (player_name, world_name, x, y, z, timestamp)
                    SELECT player_name, world_name, x, y, z, timestamp
                    FROM player_traces
                    WHERE timestamp < NOW() - INTERVAL '60 seconds'
                    RETURNING player_name
                )
                DELETE FROM player_traces
                WHERE timestamp < NOW() - INTERVAL '60 seconds';
            """
            cursor.execute(cleanup_query)
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"Warning: Cleanup failed (non-critical): {e}")

        cursor.close()
        return response, status_code

    except (Exception, psycopg2.DatabaseError) as error:
        if conn:
            conn.rollback()
        print(f"Error saving trace: {error}")
        return jsonify({"error": str(error)}), 500
    finally:
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
            INSERT INTO player_traces_archive (player_name, world_name, x, y, z, timestamp)
            SELECT player_name, world_name, x, y, z, timestamp
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
    - world: filter by world name
    - limit: number of records to return (default: 100)
    """
    player_name = request.args.get('player')
    world_name = request.args.get('world')
    limit = request.args.get('limit', 100, type=int)
    
    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        if player_name and world_name:
            query = """
                SELECT id, player_name, world_name, x, y, z, timestamp
                FROM player_traces
                WHERE player_name = %s AND world_name = %s
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (player_name, world_name, limit))
        elif player_name:
            query = """
                SELECT id, player_name, world_name, x, y, z, timestamp
                FROM player_traces
                WHERE player_name = %s
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (player_name, limit))
        elif world_name:
            query = """
                SELECT id, player_name, world_name, x, y, z, timestamp
                FROM player_traces
                WHERE world_name = %s
                ORDER BY timestamp DESC
                LIMIT %s
            """
            cursor.execute(query, (world_name, limit))
        else:
            query = """
                SELECT id, player_name, world_name, x, y, z, timestamp
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
                "world_name": row[2],
                "x": row[3],
                "y": row[4],
                "z": row[5],
                "timestamp": row[6].isoformat() if row[6] else None
            })
        
        return jsonify({"count": len(traces), "traces": traces}), 200
    except (Exception, psycopg2.DatabaseError) as error:
        print(f"Error retrieving traces: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn:
            postgresql_pool.putconn(conn)

@app.route('/create_world_view/<world>', methods=['POST'])
def create_world_view(world):
    """
    Creates a QGIS view for a specific world.
    Example: POST /create_world_view/production
    """
    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        # Call the PostgreSQL function to create the view
        cursor.execute("SELECT create_world_view(%s)", (world,))
        result = cursor.fetchone()[0]
        
        conn.commit()
        cursor.close()
        
        return jsonify({"status": "success", "message": result}), 201
    except (Exception, psycopg2.DatabaseError) as error:
        if conn:
            conn.rollback()
        print(f"Error creating view: {error}")
        return jsonify({"error": str(error)}), 500
    finally:
        if conn:
            postgresql_pool.putconn(conn)

@app.route('/', methods=['GET'])
def health_check():
    return jsonify({"status": "running"}), 200

if __name__ == '__main__':
    # Run the server on port 5000
    app.run(host='0.0.0.0', port=5000)
