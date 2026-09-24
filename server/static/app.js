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

function toast(message) {
  const el = document.getElementById("toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(() => el.classList.remove("show"), 2200);
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
    control_blocked: "App blocked",
    control_allowed: "App allowed",
    block_all: "Block All enabled",
    allow_all: "All apps allowed",
    control_removed: "Control removed"
  };
  return map[action] || action.replaceAll("_", " ");
}

function helperChip(device) {
  const online = device.online ? "online" : "";
  const label = device.online ? "Helper online" : "Helper offline";
  return `<span class="helper-chip ${online}">${label}</span>`;
}

function deviceModeChip(device) {
  if (device.block_all) {
    return `<span class="device-mode mode-lock">Lockdown</span>`;
  }
  const hasLive = device.controls.some(c => c.live);
  return hasLive
    ? `<span class="device-mode mode-live">Live</span>`
    : `<span class="device-mode mode-demo">Demo</span>`;
}

function renderDashboard() {
  const totalDevices = devices.length;
  const totalBlocked = devices.reduce((n, d) => {
    if (d.block_all) return n + d.controls.length;
    return n + d.controls.filter(c => c.blocked).length;
  }, 0);
  const liveControls = devices.reduce((n, d) => n + d.controls.filter(c => c.live).length, 0);
  const onlineHelpers = devices.filter(d => d.online).length;

  document.getElementById("totalDevices").textContent = totalDevices;
  document.getElementById("blockedCount").textContent = totalBlocked;
  document.getElementById("liveControlsCount").textContent = liveControls;
  document.getElementById("onlineCount").textContent = onlineHelpers;

  document.getElementById("deviceGrid").innerHTML = devices.map(device => {
    const blockedCount = device.block_all
      ? device.controls.length
      : device.controls.filter(c => c.blocked).length;

    const statusText = device.online
      ? `Last seen ${relTime(device.last_seen)}`
      : device.helper_paired
        ? "Ready for helper reconnect"
        : "Ready for helper pairing";

    const themeClass = device.id === "inaara" ? "theme-inaara" : "theme-nevaeh";

    return `
      <button class="device-card ${themeClass}" onclick="openDevice('${device.id}')">
        <div class="device-card-head">
          <div class="device-badge">${esc(device.avatar)}</div>
          ${helperChip(device)}
        </div>

        <h3>${esc(device.name)}</h3>
        <p class="device-sub">${esc(statusText)}</p>

        <div class="device-meta">
          <div class="device-blocked">
            <strong>${blockedCount}</strong>
            <span>${device.block_all ? "everything blocked" : "apps blocked"}</span>
          </div>
          ${deviceModeChip(device)}
        </div>
      </button>
    `;
  }).join("");
}

async function loadDevices() {
  const data = await api("/api/devices");
  devices = data.devices;

  const liveControls = devices.reduce((n, d) => n + d.controls.filter(c => c.live).length, 0);
  document.getElementById("globalState").textContent =
    `${data.apns_configured ? "Push ready" : "Push pending"} · ${liveControls} live controls`;

  renderDashboard();
}

async function openDevice(id) {
  selectedDevice = await api(`/api/devices/${id}`);
  document.getElementById("dashboardView").classList.add("hidden");
  document.getElementById("deviceView").classList.remove("hidden");
  renderSelected();
  loadAudit();
}

function showDashboard() {
  selectedDevice = null;
  document.getElementById("deviceView").classList.add("hidden");
  document.getElementById("dashboardView").classList.remove("hidden");
  loadDevices().catch(e => toast(e.message));
}

function renderSelected() {
  const d = selectedDevice;
  if (!d) return;

  document.getElementById("deviceAvatar").textContent = d.avatar;
  document.getElementById("deviceName").textContent = d.name;

  const hero = document.getElementById("deviceHero");
  hero.classList.remove("theme-nevaeh", "theme-inaara");
  hero.classList.add(d.id === "inaara" ? "theme-inaara" : "theme-nevaeh");
  document.getElementById("deviceEyebrow").textContent = d.block_all ? "Lockdown active" : "Device";
  document.getElementById("deviceModeLabel").textContent =
    d.block_all ? "Lockdown" : d.controls.some(control => control.live) ? "Live" : "Custom";
  document.getElementById("revisionText").textContent = String(d.revision);

  const dot = document.getElementById("statusDot");
  dot.className = `status-dot ${d.online ? "online" : ""}`;

  document.getElementById("deviceStatus").textContent =
    d.online
      ? `Helper online · seen ${relTime(d.last_seen)}`
      : d.helper_paired
        ? "Helper paired · currently offline"
        : "Helper not paired";

  document.getElementById("masterTitle").textContent =
    d.block_all ? "Everything blocked" : "Everything available";

  document.getElementById("masterCopy").textContent =
    d.block_all
      ? "This device is in lockdown. The helper will shield all apps and categories."
      : "Individual controls are active. Use Block All if you want a full lock.";

  document.getElementById("controlCount").textContent = d.controls.length;

  document.getElementById("controlsList").innerHTML = d.controls.length
    ? d.controls.map(control => controlCardHTML(control)).join("")
    : '<div class="empty">No controls yet.</div>';
}

function controlCardHTML(control) {
  const liveChip = control.live
    ? '<span class="chip live">Live</span>'
    : '<span class="chip demo">Demo</span>';

  const stateChip = control.blocked
    ? '<span class="chip blocked">Blocked</span>'
    : '<span class="chip allowed">Allowed</span>';

  return `
    <article class="control-card">
      <div class="control-head">
        <div class="control-icon">${esc(control.icon || "📱")}</div>
        <div class="control-chips">
          ${liveChip}
          ${stateChip}
        </div>
      </div>

      <div class="control-body">
        <h3>${esc(control.name)}</h3>
        <p>
          ${control.live
            ? "Connected to the native helper and ready to apply an Apple shield."
            : "Preview control. It will become enforceable once the helper is paired."}
        </p>
      </div>

      <div class="control-actions">
        <button
          class="btn ${control.blocked ? "btn-success" : "btn-danger"}"
          onclick="toggleControl('${control.id}', ${!control.blocked})"
        >
          ${control.blocked ? "Allow" : "Block"}
        </button>

        <button
          class="btn btn-delete"
          onclick="deleteControl('${control.id}', '${esc(control.name)}')"
          title="Remove control"
        >
          ✕
        </button>
      </div>
    </article>
  `;
}

async function toggleControl(controlId, blocked) {
  const data = await api(`/api/devices/${selectedDevice.id}/controls/${controlId}`, {
    method: "POST",
    body: { blocked }
  });
  selectedDevice = data.device;
  renderSelected();
  loadAudit();
  toast(blocked ? "App blocked" : "App allowed");
}

async function setBlockAll(blocked) {
  if (!selectedDevice) return;

  const ok = blocked
    ? confirm(`Block all apps on ${selectedDevice.name}?`)
    : confirm(`Allow all apps on ${selectedDevice.name}? This also clears individual blocks.`);

  if (!ok) return;

  const data = await api(`/api/devices/${selectedDevice.id}/block-all`, {
    method: "POST",
    body: { blocked }
  });

  selectedDevice = data.device;
  renderSelected();
  loadAudit();
  toast(blocked ? "Block All enabled" : "All apps allowed");
}

async function deleteControl(controlId, controlName) {
  if (!confirm(`Remove ${controlName} from the dashboard?`)) return;
  selectedDevice = await api(`/api/devices/${selectedDevice.id}/controls/${controlId}`, {
    method: "DELETE"
  });
  renderSelected();
  loadAudit();
  toast("Control removed");
}

async function createPairCode() {
  if (!selectedDevice) return;
  const data = await api(`/api/devices/${selectedDevice.id}/pair-code`, {
    method: "POST"
  });
  currentPairCode = data.code;
  document.getElementById("pairDeviceName").textContent = `Pair ${selectedDevice.name}`;
  document.getElementById("pairCode").textContent = data.code;
  document.getElementById("pairModal").classList.remove("hidden");
}

function closePairModal(event) {
  if (event && event.target !== event.currentTarget) return;
  document.getElementById("pairModal").classList.add("hidden");
}

async function copyPairCode() {
  await navigator.clipboard.writeText(currentPairCode);
  toast("Pair code copied");
}

async function loadAudit() {
  if (!selectedDevice) return;
  const data = await api(`/api/devices/${selectedDevice.id}/audit`);
  document.getElementById("auditList").innerHTML = data.events.length
    ? data.events.map(event => `
        <div class="audit-event">
          <div>
            <strong>${esc(actionLabel(event.action))}</strong>
            <span>${esc(event.detail || "No extra detail")}</span>
          </div>
          <span class="audit-time">${relTime(event.created_at)}</span>
        </div>
      `).join("")
    : '<div class="empty">No activity yet.</div>';
}

async function refreshSelected() {
  if (!selectedDevice) return;
  selectedDevice = await api(`/api/devices/${selectedDevice.id}`);
  renderSelected();
  loadAudit();
  toast("State refreshed");
}

if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}

loadDevices().catch(e => toast(e.message));
