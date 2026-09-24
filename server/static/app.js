let devices = [];
let selectedDevice = null;
let currentPairCode = "";

async function api(url, options = {}) {
  options.headers = { ...(options.headers || {}), "X-Kids-Control": "1" };
  if (options.body && typeof options.body !== "string") {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(options.body);
  }
  const response = await fetch(url, options);
  if (response.status === 401) {
    location.href = "/login";
    throw new Error("Signed out");
  }
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || "Request failed");
  return data;
}

function esc(value) {
  const d = document.createElement("div");
  d.textContent = value ?? "";
  return d.innerHTML;
}

function iconSvg(name) {
  const icons = {
    "app-store": '<svg viewBox="0 0 24 24"><path d="m8 17 4-7 4 7M10 13h4"/><rect x="3" y="3" width="18" height="18" rx="5"/></svg>',
    "books": '<svg viewBox="0 0 24 24"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H11v16H6.5A2.5 2.5 0 0 0 4 21.5zM20 5.5A2.5 2.5 0 0 0 17.5 3H13v16h4.5a2.5 2.5 0 0 1 2.5 2.5z"/></svg>',
    "safari": '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="m14.5 9.5-2 5-5 2 2-5z"/></svg>',
    "youtube": '<svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="4"/><path d="m10 9 5 3-5 3z"/></svg>',
    "disney": '<svg viewBox="0 0 24 24"><path d="M5 16c3-7 11-9 15-5M6 18h12"/><path d="M8 7h.01M15 5h.01"/></svg>',
    "roblox": '<svg viewBox="0 0 24 24"><path d="m8 3 13 5-5 13-13-5z"/><path d="m10 9 5 2-2 5-5-2z"/></svg>',
    "facetime": '<svg viewBox="0 0 24 24"><rect x="3" y="6" width="12" height="12" rx="2"/><path d="m15 10 6-3v10l-6-3z"/></svg>',
    "camera": '<svg viewBox="0 0 24 24"><path d="M4 7h4l1.5-2h5L16 7h4v12H4z"/><circle cx="12" cy="13" r="3"/></svg>',
    "generic": '<svg viewBox="0 0 24 24"><rect x="5" y="4" width="14" height="16" rx="3"/><path d="M9 8h6M9 12h6M9 16h4"/></svg>'
  };
  return icons[name] || icons.generic;
}

function appIconKey(name) {
  const n = String(name || "").toLowerCase();
  if (n.includes("app store")) return "app-store";
  if (n.includes("book")) return "books";
  if (n.includes("safari")) return "safari";
  if (n.includes("youtube")) return "youtube";
  if (n.includes("disney")) return "disney";
  if (n.includes("roblox")) return "roblox";
  if (n.includes("facetime")) return "facetime";
  if (n.includes("camera")) return "camera";
  return "generic";
}

function toast(message) {
  const el = document.getElementById("toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => el.classList.remove("show"), 2000);
}

function relTime(ts) {
  if (!ts) return "Never";
  const s = Math.max(0, Math.floor(Date.now() / 1000 - ts));
  if (s < 10) return "Just now";
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

function actionLabel(action) {
  const map = {
    helper_paired: "Helper paired",
    pair_code_created: "Pair code created",
    push_token_registered: "Push token registered",
    native_control_registered: "Live control added",
    control_blocked: "Application blocked",
    control_allowed: "Application allowed",
    block_all: "Block All enabled",
    allow_all: "All applications allowed",
    control_removed: "Control removed"
  };
  return map[action] || action.replaceAll("_", " ");
}

function policyInfo(device) {
  if (device.block_all) return { text: "Lockdown", cls: "policy-lock" };
  if (device.controls.some(c => c.live)) return { text: "Live", cls: "policy-live" };
  return { text: "Preview", cls: "policy-demo" };
}

function helperStatus(device) {
  if (device.online) return { text: "Online", cls: "status-online" };
  return { text: device.helper_paired ? "Offline" : "Not paired", cls: "status-offline" };
}

function renderDashboard() {
  const totalDevices = devices.length;
  const totalBlocked = devices.reduce((n, d) => n + (d.block_all ? d.controls.length : d.controls.filter(c => c.blocked).length), 0);
  const liveControls = devices.reduce((n, d) => n + d.controls.filter(c => c.live).length, 0);
  const onlineHelpers = devices.filter(d => d.online).length;

  document.getElementById("totalDevices").textContent = totalDevices;
  document.getElementById("blockedCount").textContent = totalBlocked;
  document.getElementById("liveControlsCount").textContent = liveControls;
  document.getElementById("onlineCount").textContent = onlineHelpers;
  document.getElementById("deviceCountBadge").textContent = `${totalDevices} device${totalDevices === 1 ? "" : "s"}`;

  document.getElementById("deviceTableBody").innerHTML = devices.map(device => {
    const blocked = device.block_all ? device.controls.length : device.controls.filter(c => c.blocked).length;
    const status = helperStatus(device);
    const policy = policyInfo(device);
    return `
      <tr class="device-row" onclick="openDevice('${device.id}')">
        <td>
          <div class="device-cell">
            <div class="device-icon">${esc(device.avatar)}</div>
            <div class="device-cell-copy"><strong>${esc(device.name)}</strong><span>Apple iPad</span></div>
          </div>
        </td>
        <td><span class="status-badge ${status.cls}">${status.text}</span></td>
        <td><span class="policy-badge ${policy.cls}">${policy.text}</span></td>
        <td>${blocked} blocked</td>
        <td>${device.last_seen ? relTime(device.last_seen) : "No check-in"}</td>
        <td><button class="manage-link" onclick="event.stopPropagation();openDevice('${device.id}')">Manage</button></td>
      </tr>`;
  }).join("");

  document.getElementById("deviceMobileList").innerHTML = devices.map(device => {
    const blocked = device.block_all ? device.controls.length : device.controls.filter(c => c.blocked).length;
    const status = helperStatus(device);
    const policy = policyInfo(device);
    return `
      <article class="mobile-device-card">
        <div class="mobile-device-head">
          <div class="device-icon">${esc(device.avatar)}</div>
          <div class="device-cell-copy"><strong>${esc(device.name)}</strong><span>Apple iPad</span></div>
          <span class="status-badge ${status.cls}">${status.text}</span>
        </div>
        <div class="mobile-device-meta">
          <div class="mobile-meta"><span>Policy</span><strong>${policy.text}</strong></div>
          <div class="mobile-meta"><span>Restrictions</span><strong>${blocked} blocked</strong></div>
          <div class="mobile-meta"><span>Last check-in</span><strong>${device.last_seen ? relTime(device.last_seen) : "Never"}</strong></div>
          <div class="mobile-meta"><span>Controls</span><strong>${device.controls.length}</strong></div>
        </div>
        <div class="mobile-device-actions"><button class="btn btn-primary" onclick="openDevice('${device.id}')">Manage device</button></div>
      </article>`;
  }).join("");
}

async function loadDevices() {
  const data = await api("/api/devices");
  devices = data.devices;
  const liveControls = devices.reduce((n, d) => n + d.controls.filter(c => c.live).length, 0);
  document.getElementById("globalState").textContent = `${data.apns_configured ? "Push ready" : "Push pending"} · ${liveControls} live`;
  renderDashboard();
}

async function openDevice(id) {
  selectedDevice = await api(`/api/devices/${id}`);
  document.getElementById("dashboardView").classList.add("hidden");
  document.getElementById("deviceView").classList.remove("hidden");
  renderSelected();
  loadAudit();
  window.scrollTo({ top: 0, behavior: "instant" });
}

function showDashboard() {
  selectedDevice = null;
  document.getElementById("deviceView").classList.add("hidden");
  document.getElementById("dashboardView").classList.remove("hidden");
  loadDevices().catch(e => toast(e.message));
  window.scrollTo({ top: 0, behavior: "instant" });
}

function renderSelected() {
  const d = selectedDevice;
  if (!d) return;

  const status = helperStatus(d);
  const policy = policyInfo(d);

  document.getElementById("deviceName").textContent = d.name;
  document.getElementById("deviceIdentityName").textContent = d.name;
  document.getElementById("deviceAvatar").textContent = d.avatar;
  document.getElementById("deviceStatus").textContent = d.online
    ? `Helper online · checked in ${relTime(d.last_seen)}`
    : d.helper_paired ? "Helper paired · currently offline" : "Native helper not paired";

  const dot = document.getElementById("statusDot");
  dot.className = `status-dot ${d.online ? "online" : ""}`;

  const mgmtDot = document.getElementById("managementDot");
  mgmtDot.className = `status-dot ${d.online ? "online" : ""}`;
  document.getElementById("managementStatus").textContent = status.text;
  document.getElementById("deviceModeLabel").textContent = policy.text;
  document.getElementById("revisionText").textContent = String(d.revision);
  document.getElementById("masterTitle").textContent = d.block_all ? "Lockdown policy active" : "Standard access policy";
  document.getElementById("masterCopy").textContent = d.block_all
    ? "All supported application categories are set to blocked."
    : "Individual application restrictions are being applied.";
  document.getElementById("controlCount").textContent = d.controls.length;

  const rows = d.controls.map(control => {
    const source = control.live ? "Live helper" : "Preview";
    const sourceClass = control.live ? "source-badge live" : "source-badge";
    return `
      <tr>
        <td>
          <div class="app-cell">
            <div class="app-symbol">${iconSvg(appIconKey(control.name))}</div>
            <div class="app-cell-copy"><strong>${esc(control.name)}</strong><span>Application control</span></div>
          </div>
        </td>
        <td><span class="${sourceClass}">${source}</span></td>
        <td><span class="state-text ${control.blocked ? "state-blocked" : "state-allowed"}">${control.blocked ? "Blocked" : "Allowed"}</span></td>
        <td><button class="btn ${control.blocked ? "btn-success" : "btn-danger"}" onclick="toggleControl('${control.id}', ${!control.blocked})">${control.blocked ? "Allow" : "Block"}</button></td>
        <td><button class="remove-btn" onclick="deleteControl('${control.id}', '${esc(control.name)}')" title="Remove control"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button></td>
      </tr>`;
  }).join("");

  document.getElementById("controlsList").innerHTML = rows || '<tr><td colspan="5"><div class="empty">No application controls configured.</div></td></tr>';

  document.getElementById("controlsMobileList").innerHTML = d.controls.map(control => `
    <article class="mobile-control-card">
      <div class="mobile-control-top">
        <div class="app-symbol">${iconSvg(appIconKey(control.name))}</div>
        <div class="app-cell-copy"><strong>${esc(control.name)}</strong><span>${control.live ? "Live helper" : "Preview control"}</span></div>
        <span class="state-text ${control.blocked ? "state-blocked" : "state-allowed"}">${control.blocked ? "Blocked" : "Allowed"}</span>
      </div>
      <div class="mobile-control-actions">
        <button class="btn ${control.blocked ? "btn-success" : "btn-danger"}" onclick="toggleControl('${control.id}', ${!control.blocked})">${control.blocked ? "Allow application" : "Block application"}</button>
        <button class="remove-btn" onclick="deleteControl('${control.id}', '${esc(control.name)}')"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
      </div>
    </article>
  `).join("") || '<div class="empty">No application controls configured.</div>';
}

async function toggleControl(controlId, blocked) {
  const data = await api(`/api/devices/${selectedDevice.id}/controls/${controlId}`, {
    method: "POST",
    body: { blocked }
  });
  selectedDevice = data.device;
  renderSelected();
  loadAudit();
  toast(blocked ? "Application blocked" : "Application allowed");
}

async function setBlockAll(blocked) {
  if (!selectedDevice) return;
  const message = blocked
    ? `Apply Block All to ${selectedDevice.name}?`
    : `Allow all applications on ${selectedDevice.name}? This also clears individual blocks.`;
  if (!confirm(message)) return;

  const data = await api(`/api/devices/${selectedDevice.id}/block-all`, {
    method: "POST",
    body: { blocked }
  });
  selectedDevice = data.device;
  renderSelected();
  loadAudit();
  toast(blocked ? "Block All applied" : "All applications allowed");
}

async function deleteControl(controlId, controlName) {
  if (!confirm(`Remove ${controlName} from managed controls?`)) return;
  selectedDevice = await api(`/api/devices/${selectedDevice.id}/controls/${controlId}`, { method: "DELETE" });
  renderSelected();
  loadAudit();
  toast("Control removed");
}

async function createPairCode() {
  if (!selectedDevice) return;
  const data = await api(`/api/devices/${selectedDevice.id}/pair-code`, { method: "POST" });
  currentPairCode = data.code;
  document.getElementById("pairDeviceName").textContent = `Enroll ${selectedDevice.name}`;
  document.getElementById("pairCode").textContent = data.code;
  document.getElementById("pairModal").classList.remove("hidden");
}

function closePairModal(event) {
  if (event && event.target !== event.currentTarget) return;
  document.getElementById("pairModal").classList.add("hidden");
}

async function copyPairCode() {
  await navigator.clipboard.writeText(currentPairCode);
  toast("Enrollment code copied");
}

async function loadAudit() {
  if (!selectedDevice) return;
  const data = await api(`/api/devices/${selectedDevice.id}/audit`);
  document.getElementById("auditList").innerHTML = data.events.length
    ? data.events.map(event => `
        <div class="audit-event">
          <div><strong>${esc(actionLabel(event.action))}</strong><span>${esc(event.detail || "Management event")}</span></div>
          <span class="audit-time">${relTime(event.created_at)}</span>
        </div>`).join("")
    : '<div class="empty">No activity recorded yet.</div>';
}

async function refreshSelected() {
  if (!selectedDevice) return;
  selectedDevice = await api(`/api/devices/${selectedDevice.id}`);
  renderSelected();
  loadAudit();
  toast("Device state refreshed");
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}

loadDevices().catch(e => toast(e.message));
