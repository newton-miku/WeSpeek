
async function hmacSha256(key, message) {
    const enc = new TextEncoder();
    const keyData = await crypto.subtle.importKey(
        "raw",
        enc.encode(key),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
    );
    const signature = await crypto.subtle.sign(
        "HMAC",
        keyData,
        enc.encode(message)
    );
    return Array.from(new Uint8Array(signature))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}

const loginOverlay = document.getElementById('loginOverlay');
const loginBtn = document.getElementById('loginBtn');
const adminKeyInput = document.getElementById('adminKey');
const loginError = document.getElementById('loginError');

// Try to get token from main app storage or local storage
let adminKey = localStorage.getItem('wspeek_admin_token') || localStorage.getItem('wspeek_admin_key');
let refreshTimer = null;
let cachedAuth = null; // { authStr, exp }

if (!adminKey) {
    loginOverlay.style.display = 'flex';
} else {
    // Attempt auto-refresh using stored token; if unauthorized, show login without clearing token
    startRefresh();
}

loginBtn.addEventListener('click', async () => {
    const key = adminKeyInput.value.trim();
    if (!key) return;
    
    // Test auth
    if (await verifyKey(key)) {
        adminKey = key;
        // Save to the same key as the main app for convenience
        localStorage.setItem('wspeek_admin_token', key);
        loginOverlay.style.display = 'none';
        startRefresh();
    } else {
        loginError.style.display = 'block';
    }
});

async function getAuthHeader(key) {
    // Use challenge-based auth like main app
    if (cachedAuth && (Date.now() / 1000) < cachedAuth.exp) {
        return cachedAuth.authStr;
    }
    const res = await fetch('/api/admin/challenge', { method: 'GET' });
    if (!res.ok) throw new Error('challenge failed');
    const data = await res.json();
    const nonce = data.nonce;
    const exp = data.exp;
    const mac = await hmacSha256(key, nonce);
    const authStr = `${nonce}:${mac}`;
    cachedAuth = { authStr, exp: exp - 5 };
    return authStr;
}

async function verifyKey(key) {
    try {
        const auth = await getAuthHeader(key);
        const res = await fetch('/api/admin/status', {
            headers: { 'X-Admin-Auth': auth }
        });
        return res.ok;
    } catch (e) {
        return false;
    }
}

function startRefresh() {
    fetchStats();
    refreshTimer = setInterval(fetchStats, 3000);
}

async function fetchStats() {
    if (!adminKey) return;
    
    try {
        const auth = await getAuthHeader(adminKey);
        const res = await fetch('/api/admin/status', {
            headers: { 'X-Admin-Auth': auth }
        });
        
        if (res.status === 401) {
            // Token might be invalid (or key changed); do not clear stored token
            cachedAuth = null;
            loginOverlay.style.display = 'flex';
            return;
        }
        
        if (!res.ok) return;
        
        // Auth success, ensure overlay is hidden
        if (loginOverlay.style.display !== 'none') {
            loginOverlay.style.display = 'none';
        }

        const data = await res.json();
        updateUI(data);
    } catch (e) {
        console.error("Failed to fetch stats", e);
    }
}

let lastData = null;
let lastFetchTime = 0;

function updateUI(data) {
    const now = Date.now();
    let deltaTime = 0;
    if (lastFetchTime > 0) {
        deltaTime = (now - lastFetchTime) / 1000;
    }

    document.getElementById('roomCount').textContent = data.roomCount;
    document.getElementById('peerCount').textContent = data.peerCount;
    document.getElementById('avgPing').textContent = data.avgPing.toFixed(1);
    document.getElementById('avgQueue').textContent = data.avgQueueSize.toFixed(2);
    document.getElementById('totalSent').textContent = formatNumber(data.totalPacketsSent);
    
    const totalPackets = data.totalPacketsSent + data.totalPacketsLost;
    let lossRate = 0;
    if (totalPackets > 0) {
        lossRate = (data.totalPacketsLost / totalPackets) * 100;
    }
    document.getElementById('dropRate').textContent = lossRate.toFixed(4);

    // New Metrics
    document.getElementById('uptime').textContent = formatUptime(data.uptime);
    document.getElementById('goroutines').textContent = data.goroutineCount;
    document.getElementById('memAlloc').textContent = (data.allocMemory / 1024 / 1024).toFixed(2);
    document.getElementById('memSys').textContent = (data.sysMemory / 1024 / 1024).toFixed(2);
    
    document.getElementById('lastUpdated').textContent = 'Last updated: ' + new Date().toLocaleTimeString();

    // Speed Calculation (Global)
    let txSpeed = 0;
    let rxSpeed = 0;
    
    // Only calculate speed if we have previous data and time difference is reasonable
    if (lastData && deltaTime > 0 && deltaTime < 60) {
        if (data.totalBytesSent >= lastData.totalBytesSent) {
             txSpeed = (data.totalBytesSent - lastData.totalBytesSent) / deltaTime;
        }
        if (data.totalBytesReceived >= lastData.totalBytesReceived) {
             rxSpeed = (data.totalBytesReceived - lastData.totalBytesReceived) / deltaTime;
        }
    }
    
    const txSpeedElem = document.getElementById('txSpeed');
    const rxSpeedElem = document.getElementById('rxSpeed');
    if (txSpeedElem) txSpeedElem.textContent = (txSpeed / 1024).toFixed(2);
    if (rxSpeedElem) rxSpeedElem.textContent = (rxSpeed / 1024).toFixed(2);

    // Render Rooms
    const tbody = document.getElementById('roomsTableBody');
    if (tbody && data.rooms) {
        tbody.innerHTML = '';
        data.rooms.forEach(room => {
            // Calculate per-room speed
            let rTxSpeed = 0;
            let rRxSpeed = 0;
            
            if (lastData && lastData.rooms && deltaTime > 0 && deltaTime < 60) {
                const prevRoom = lastData.rooms.find(r => r.id === room.id);
                if (prevRoom) {
                     if (room.bytesSent >= prevRoom.bytesSent) {
                        rTxSpeed = (room.bytesSent - prevRoom.bytesSent) / deltaTime;
                     }
                     if (room.bytesReceived >= prevRoom.bytesReceived) {
                        rRxSpeed = (room.bytesReceived - prevRoom.bytesReceived) / deltaTime;
                     }
                }
            }

            const tr = document.createElement('tr');
            tr.style.borderBottom = '1px solid var(--card-border)';
            // Use lighter color for text if needed, or inherit
            tr.innerHTML = `
                <td style="padding: 12px;">${room.id}</td>
                <td style="padding: 12px;">${room.name || '-'}</td>
                <td style="padding: 12px;">${room.peerCount}</td>
                <td style="padding: 12px;">${room.avgPing.toFixed(1)} ms</td>
                <td style="padding: 12px;">${(rTxSpeed / 1024).toFixed(2)} KB/s</td>
                <td style="padding: 12px;">${(rRxSpeed / 1024).toFixed(2)} KB/s</td>
            `;
            tbody.appendChild(tr);
        });
        
        if (data.rooms.length === 0) {
             const tr = document.createElement('tr');
             tr.innerHTML = `<td colspan="6" style="padding: 12px; text-align: center; color: var(--text-secondary);">No active rooms</td>`;
             tbody.appendChild(tr);
        }
    }

    lastData = data;
    lastFetchTime = now;
}

function formatUptime(seconds) {
    const d = Math.floor(seconds / (3600*24));
    const h = Math.floor(seconds % (3600*24) / 3600);
    const m = Math.floor(seconds % 3600 / 60);
    const s = seconds % 60;
    
    const parts = [];
    if (d > 0) parts.push(d + 'd');
    if (h > 0) parts.push(h + 'h');
    if (m > 0) parts.push(m + 'm');
    parts.push(s + 's');
    return parts.join(' ');
}

function formatNumber(num) {
    return new Intl.NumberFormat().format(num);
}
