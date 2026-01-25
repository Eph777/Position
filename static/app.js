// API Base URL
const API_BASE = '';

// DOM Elements
const startWorldForm = document.getElementById('startWorldForm');
const worldsList = document.getElementById('worldsList');
const refreshBtn = document.getElementById('refreshBtn');
const statusMessage = document.getElementById('statusMessage');

// Show status message
function showStatus(message, type = 'info') {
    statusMessage.textContent = message;
    statusMessage.className = `status-message ${type} show`;

    setTimeout(() => {
        statusMessage.classList.remove('show');
    }, 5000);
}

// Start World Handler
startWorldForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const worldName = document.getElementById('worldName').value.trim();
    const port = parseInt(document.getElementById('port').value);
    const mapPortInput = document.getElementById('mapPort').value.trim();
    const mapPort = mapPortInput ? parseInt(mapPortInput) : null;
    const enableService = document.getElementById('enableService').checked;

    const data = {
        world: worldName,
        port: port,
        enable_service: enableService
    };

    if (mapPort) {
        data.map_port = mapPort;
    }

    try {
        const response = await fetch(`${API_BASE}/api/world/start`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (response.ok) {
            showStatus(`${result.message}`, 'success');
            startWorldForm.reset();
            loadWorlds(); // Refresh world list
        } else {
            showStatus(`Error: ${result.error || 'Failed to start world'}`, 'error');
        }
    } catch (error) {
        showStatus(`Error: ${error.message}`, 'error');
    }
});

// Stop World Handler
async function stopWorld(worldName) {
    if (!confirm(`Are you sure you want to stop world "${worldName}"?`)) {
        return;
    }

    try {
        const response = await fetch(`${API_BASE}/api/world/stop`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ world: worldName })
        });

        const result = await response.json();

        if (response.ok) {
            showStatus(`${result.message}`, 'success');
            loadWorlds(); // Refresh world list
        } else {
            showStatus(`Error: ${result.error || 'Failed to stop world'}`, 'error');
        }
    } catch (error) {
        showStatus(`Error: ${error.message}`, 'error');
    }
}

// Load and display worlds
async function loadWorlds() {
    worldsList.innerHTML = '<p class="loading">Loading...</p>';

    try {
        const response = await fetch(`${API_BASE}/api/worlds/list`);
        const result = await response.json();

        if (!response.ok) {
            throw new Error(result.error || 'Failed to load worlds');
        }

        if (result.worlds.length === 0) {
            worldsList.innerHTML = '<p class="loading">No running worlds</p>';
            return;
        }

        worldsList.innerHTML = result.worlds.map(world => createWorldCard(world)).join('');
    } catch (error) {
        worldsList.innerHTML = `<p class="loading">Error: ${error.message}</p>`;
    }
}

// Create world card HTML
function createWorldCard(world) {
    const isGameRunning = world.game_server === 'active';
    const isMapRunning = world.map_renderer === 'active';

    return `
        <div class="world-item">
            <div class="world-info">
                <h3>
                    ${world.world}
                    <span class="status-badge ${isGameRunning ? 'status-active' : 'status-inactive'}">
                        ${isGameRunning ? '● Online' : '○ Offline'}
                    </span>
                </h3>
                <div class="world-details">
                    <span>Game Server: <strong>${world.game_server}</strong></span>
                    <span>Map Renderer: <strong>${world.map_renderer || 'N/A'}</strong></span>
                    <span>Map Server: <strong>${world.map_server || 'N/A'}</strong></span>
                </div>
            </div>
            <div class="world-actions">
                <button class="btn btn-danger" onclick="stopWorld('${world.world}')">
                    <span class="btn-icon">⏹</span> Stop
                </button>
            </div>
        </div>
    `;
}

// Refresh button handler
refreshBtn.addEventListener('click', loadWorlds);

// Auto-refresh every 10 seconds
setInterval(loadWorlds, 10000);

// Initial load
loadWorlds();
