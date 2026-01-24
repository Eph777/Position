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
                    INSERT INTO player_traces_archive (player_name, x, y, z, timestamp)
                    SELECT player_name, x, y, z, timestamp
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

import bcrypt
import json

# Compile BCRYPT for password hashing
# Ensure 'bcrypt' is installed: pip install bcrypt

@app.route('/team/create', methods=['POST'])
def create_team():
    """
    Creates a new team.
    Input: { "team_name": "Alpha", "leader_name": "Player1", "password": "secret" }
    """
    data = request.json
    if not data or not all(k in data for k in ("team_name", "leader_name", "password")):
        return jsonify({"error": "Missing fields"}), 400

    team_name = data['team_name']
    leader_name = data['leader_name']
    password = data['password']

    # Hash password
    hashed_pw = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        insert_query = """
            INSERT INTO teams (team_name, leader_name, password_hash)
            VALUES (%s, %s, %s)
            RETURNING team_id
        """
        cursor.execute(insert_query, (team_name, leader_name, hashed_pw))
        team_id = cursor.fetchone()[0]
        
        # Auto-assign leader to team
        update_player_query = """
            INSERT INTO players (player_name, team_id)
            VALUES (%s, %s)
            ON CONFLICT (player_name) 
            DO UPDATE SET team_id = EXCLUDED.team_id
        """
        cursor.execute(update_player_query, (leader_name, team_id))
        
        conn.commit()
        cursor.close()
        return jsonify({"status": "success", "team_id": team_id}), 201
    except psycopg2.IntegrityError:
        if conn: conn.rollback()
        return jsonify({"error": "Team name already exists"}), 409
    except (Exception, psycopg2.DatabaseError) as error:
        if conn: conn.rollback()
        print(f"Error creating team: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn: postgresql_pool.putconn(conn)

@app.route('/auth/leader', methods=['POST'])
def auth_leader():
    """
    Verifies leader password.
    Input: { "leader_name": "Player1", "password": "secret" }
    """
    data = request.json
    if not data or not all(k in data for k in ("leader_name", "password")):
        return jsonify({"error": "Missing fields"}), 400

    leader = data['leader_name']
    password = data['password']

    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        query = "SELECT password_hash FROM teams WHERE leader_name = %s"
        cursor.execute(query, (leader,))
        row = cursor.fetchone()
        cursor.close()
        
        if row and bcrypt.checkpw(password.encode('utf-8'), row[0].encode('utf-8')):
            return jsonify({"status": "success"}), 200
        else:
            return jsonify({"error": "Invalid credentials"}), 401
            
    except (Exception, psycopg2.DatabaseError) as error:
        print(f"Error authenticating leader: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn: postgresql_pool.putconn(conn)

@app.route('/sync/player', methods=['POST'])
def sync_player():
    """
    Upserts player position and inventory.
    Input: { "player_name": "p1", "x": 0, "y": 0, "z": 0, "inventory_json": {...} }
    """
    data = request.json
    if not data or 'player_name' not in data:
        return jsonify({"error": "Missing player_name"}), 400

    player = data['player_name']
    x = data.get('x', 0)
    y = data.get('y', 0)
    z = data.get('z', 0)
    inv = data.get('inventory_json', {}) # Expecting dict or string, will cast to jsonb

    # Ensure inventory is valid JSON string for DB if passed as dict
    if isinstance(inv, dict):
        inv = json.dumps(inv)

    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        upsert_query = """
            INSERT INTO players (player_name, pos_x, pos_y, pos_z, inventory_data, last_update)
            VALUES (%s, %s, %s, %s, %s, NOW())
            ON CONFLICT (player_name) 
            DO UPDATE SET
                pos_x = EXCLUDED.pos_x,
                pos_y = EXCLUDED.pos_y,
                pos_z = EXCLUDED.pos_z,
                inventory_data = EXCLUDED.inventory_data,
                last_update = NOW()
        """
        cursor.execute(upsert_query, (player, x, y, z, inv))
        conn.commit()
        cursor.close()
        
        return jsonify({"status": "success"}), 200
    except (Exception, psycopg2.DatabaseError) as error:
        if conn: conn.rollback()
        print(f"Error syncing player: {error}")
        return jsonify({"error": str(error)}), 500
    finally:
        if conn: postgresql_pool.putconn(conn)

@app.route('/team/roster/<leader_name>', methods=['GET'])
def get_team_roster(leader_name):
    """
    Returns list of members and positions for the leader's team.
    """
    conn = None
    try:
        conn = postgresql_pool.getconn()
        cursor = conn.cursor()
        
        # 1. Get Team ID for leader
        cursor.execute("SELECT team_id FROM teams WHERE leader_name = %s", (leader_name,))
        row = cursor.fetchone()
        
        if not row:
            cursor.close()
            return jsonify({"error": "Leader not found or no team"}), 404
            
        team_id = row[0]
        
        # 2. Get Members
        query = """
            SELECT player_name, pos_x, pos_y, pos_z, last_update 
            FROM players 
            WHERE team_id = %s
        """
        cursor.execute(query, (team_id,))
        members = []
        for r in cursor.fetchall():
            members.append({
                "name": r[0],
                "x": r[1],
                "y": r[2],
                "z": r[3],
                "last_update": r[4].isoformat() if r[4] else None
            })
            
        cursor.close()
        return jsonify({"team_id": team_id, "members": members}), 200
        
    except (Exception, psycopg2.DatabaseError) as error:
        print(f"Error getting roster: {error}")
        return jsonify({"error": "Database error"}), 500
    finally:
        if conn: postgresql_pool.putconn(conn)

if __name__ == '__main__':
    # Run the server on port 5000
    app.run(host='0.0.0.0', port=5000)
