import os
import asyncpg
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import Optional, List
import logging

# Configuration
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_NAME = os.environ.get("DB_NAME", "luanti_db")
DB_USER = os.environ.get("DB_USER", "luanti") # The middleware user (superuser/owner)
DB_PASS = os.environ.get("DB_PASS", "postgres123")
DB_PORT = os.environ.get("DB_PORT", "5432")

app = FastAPI()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Models
class TeamCreate(BaseModel):
    name: str
    password: str

class PlayerPosition(BaseModel):
    x: float
    y: float
    z: float

class PlayerSync(BaseModel):
    player: str
    team: Optional[str] = None
    pos: Optional[PlayerPosition] = None
    inventory: Optional[dict] = None

class JoinRequest(BaseModel):
    player: str
    team: str

class ApproveRequest(BaseModel):
    player_name: str

# Database Connection
async def get_db_pool():
    # Only creating a pool for the middleware user
    retries = 10
    for i in range(retries):
        try:
            pool = await asyncpg.create_pool(
                user=DB_USER,
                password=DB_PASS,
                database=DB_NAME,
                host=DB_HOST,
                port=DB_PORT
            )
            logger.info("Connected to Database.")
            return pool
        except (OSError, asyncpg.CannotConnectNowError, asyncpg.PostgresConnectionError) as e:
            if i == retries - 1:
                logger.error(f"Failed to connect to DB after {retries} attempts: {e}")
                raise e
            logger.warning(f"DB not ready yet, retrying in 1s ({i+1}/{retries})...")
            import asyncio
            await asyncio.sleep(1)

@app.on_event("startup")
async def startup():
    app.state.pool = await get_db_pool()

@app.on_event("shutdown")
async def shutdown():
    await app.state.pool.close()

# Helper: Verify Team Credentials by checking connection
async def verify_team_credentials(team_name: str, team_pass: str):
    """
    Verifies team credentials by attempting to connect to Postgres as that user.
    """
    try:
        conn = await asyncpg.connect(
            user=team_name,
            password=team_pass,
            database=DB_NAME,
            host=DB_HOST,
            port=DB_PORT
        )
        await conn.close()
        return True
    except Exception as e:
        logger.warning(f"Auth failed for {team_name}: {e}")
        return False

# Dependency for Team Auth
async def get_current_team(
    x_team_name: str = Header(None, alias="X-Team-Name"),
    x_team_pass: str = Header(None, alias="X-Team-Pass")
):
    if not x_team_name or not x_team_pass:
        raise HTTPException(status_code=401, detail="Missing auth headers")
    
    if not await verify_team_credentials(x_team_name, x_team_pass):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    return x_team_name

# --- API Endpoints ---

@app.get("/")
async def serve_index():
    return FileResponse("static/index.html")

# 1. Team Management

@app.post("/api/team")
async def create_team(team: TeamCreate):
    """
    Creates a new Team:
    1. Inserts into 'teams' table.
    2. Creates Postgres User.
    3. Grants permissions.
    """
    async with app.state.pool.acquire() as conn:
        # Check if team exists
        exists = await conn.fetchval("SELECT name FROM teams WHERE name = $1", team.name)
        if exists:
            raise HTTPException(status_code=400, detail="Team already exists")

        tr = conn.transaction()
        await tr.start()
        try:
            # 1. Metadata
            await conn.execute("INSERT INTO teams (name) VALUES ($1)", team.name)

            # 2. Database User
            # WARNING: Parametrized queries don't work for identifiers/passwords in DDL usually. 
            # We must sanitize carefully or use format.
            # Ideally use a strict allowed charset for team names.
            if not team.name.isalnum():
                raise HTTPException(status_code=400, detail="Team name must be alphanumeric")
            
            # Create User
            await conn.execute(f'CREATE USER "{team.name}" WITH PASSWORD \'{team.password}\'')
            
            # Grant Connect
            await conn.execute(f'GRANT CONNECT ON DATABASE "{DB_NAME}" TO "{team.name}"')
            await conn.execute(f'GRANT USAGE ON SCHEMA public TO "{team.name}"')
            
            # Grant Select on Players (RLS handles visibility)
            await conn.execute(f'GRANT SELECT ON players TO "{team.name}"')
            
            # Grant Select on View (optional, if they use view)
            await conn.execute(f'GRANT SELECT ON v_tactical_map TO "{team.name}"')

            await tr.commit()
            return {"status": "created", "team": team.name}
        except Exception as e:
            await tr.rollback()
            logger.error(f"Create team failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))

@app.delete("/api/team/{name}")
async def delete_team(name: str, current_team: str = Depends(get_current_team)):
    if name != current_team:
        raise HTTPException(status_code=403, detail="Cannot delete other teams")

    async with app.state.pool.acquire() as conn:
        tr = conn.transaction()
        await tr.start()
        try:
            # Drop User (requires Drop Objects first usually, CASCADE handles user objects?)
            # Postgres needs simple Drop User. But owning strings...
            # We set ON DELETE CASCADE on foreign keys, but DB User ownership is different.
            # The 'players' rows are owned by 'luanti' (middleware), so dropping user is safe for data?
            # No, 'teams' row might refer.
            
            # 1. Delete data
            await conn.execute("DELETE FROM teams WHERE name = $1", name) # Cascades to players
            
            # 2. Drop Role
            await conn.execute(f'DROP USER IF EXISTS "{name}"')
            
            await tr.commit()
            return {"status": "deleted"}
        except Exception as e:
            await tr.rollback()
            raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/team/requests")
async def get_requests(current_team: str = Depends(get_current_team)):
    async with app.state.pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT player_name, to_char(last_update, 'YYYY-MM-DD HH24:MI:SS') as last_update 
            FROM players 
            WHERE team_name = $1 AND status = 'pending'
            """, 
            current_team
        )
        return {"players": [{"name": r["player_name"], "last_update": r["last_update"]} for r in rows]}

@app.get("/api/team/roster")
async def get_roster(current_team: str = Depends(get_current_team)):
    async with app.state.pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT player_name, to_char(last_update, 'YYYY-MM-DD HH24:MI:SS') as last_update 
            FROM players 
            WHERE team_name = $1 AND status = 'active'
            """, 
            current_team
        )
        return {"players": [{"name": r["player_name"], "last_update": r["last_update"]} for r in rows]}

@app.post("/api/team/approve")
async def approve_player(req: ApproveRequest, current_team: str = Depends(get_current_team)):
    async with app.state.pool.acquire() as conn:
        res = await conn.execute(
            "UPDATE players SET status = 'active' WHERE player_name = $1 AND team_name = $2",
            req.player_name, current_team
        )
        if "0" in res:
             raise HTTPException(status_code=404, detail="Player not found or not in this team")
        return {"status": "approved", "player": req.player_name}

# 2. Player Interaction (Luanti Mod)

@app.post("/api/join")
async def join_team(join: JoinRequest):
    """
    Player requests to join a team.
    Status set to 'pending'.
    """
    async with app.state.pool.acquire() as conn:
        # Check team exists
        team_exists = await conn.fetchval("SELECT name FROM teams WHERE name = $1", join.team)
        if not team_exists:
            raise HTTPException(status_code=404, detail="Team does not exist")

        # Upsert player
        await conn.execute(
            """
            INSERT INTO players (player_name, team_name, x, y, z, status)
            VALUES ($1, $2, 0, 0, 0, 'pending')
            ON CONFLICT (player_name) 
            DO UPDATE SET team_name = $2, status = 'pending', last_update = NOW()
            """,
            join.player, join.team
        )
        return {"status": "request_sent", "message": f"Join request sent to {join.team}"}

@app.post("/position") # Legacy URL kept or updated
@app.post("/sync/player")
async def sync_player(data: PlayerSync):
    """
    Updates player position/inventory.
    Requires player to be in a team? 
    We update regardless, but if they have no team, it might fail FK?
    Actually, we should check if they are in a team. 
    If they are not in DB, we can't update.
    The Mod should assume they are joined.
    """
    async with app.state.pool.acquire() as conn:
        # Check if player exists
        current = await conn.fetchrow("SELECT team_name, status FROM players WHERE player_name = $1", data.player)
        
        if not current:
            # Player unknown (hasn't joined via /join command yet)
            # We can't insert them without a team (FK violation).
            # Return distinct code so Mod can prompt user to join.
            return {"status": "error", "code": "NO_TEAM", "message": "You must join a team first! Use /join <team>"}
        
        team_name = current['team_name']
        status = current['status']
        
        # Only update if data provided
        if data.pos:
            await conn.execute(
                """
                UPDATE players 
                SET x = $2, y = $3, z = $4, last_update = NOW()
                WHERE player_name = $1
                """,
                data.player, data.pos.x, data.pos.y, data.pos.z
            )
        
        if data.inventory:
            await conn.execute(
                "UPDATE players SET inventory_json = $2 WHERE player_name = $1",
                data.player, data.inventory
            )
            
        return {"status": "synced", "team": team_name, "player_status": status}

app.mount("/static", StaticFiles(directory="static"), name="static")
