var maxDisplayLength = 160

function boundedText(value) {
  value = String(value || "")
  return value.length > maxDisplayLength ? value.slice(0, maxDisplayLength - 1) + "…" : value
}

function appId(window) {
  if (!window) return ""
  if (window.wayland && window.wayland.appId) return String(window.wayland.appId)
  var ipc = window.lastIpcObject || {}
  return String(ipc.class || ipc.initialClass || "")
}

function label(window) {
  return boundedText(window && window.title ? window.title : (appId(window) || "Untitled"))
}

function detail(window) {
  if (!window) return ""
  var value = appId(window)
  if (window.workspace) value += (value ? " · " : "") + "ws " + String(window.workspace.id)
  return boundedText(value)
}

// ListView rows must not retain compositor-owned QObjects after a window closes.
function windowSnapshot(window) {
  return {
    address: String(window.address || ""),
    title: String(window.title || ""),
    activated: !!window.activated,
    workspace: window.workspace ? { id: window.workspace.id } : null,
    lastIpcObject: { class: appId(window), focusHistoryID: historyRank(window) }
  }
}

function windowForAddress(values, address) {
  var key = addressKey(address)
  if (!key) return null
  for (var i = 0; i < values.length; i++)
    if (addressKey(values[i]) === key) return values[i]
  return null
}

function normalizedAppIdentity(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]/g, "")
}

// Window app IDs and .desktop IDs are not always identical (for example,
// "code" vs "visual-studio-code"). Prefer exact matches, then use a small,
// deterministic fuzzy match across the desktop ID, name, and icon name.
function desktopEntryForWindow(window, entries) {
  var needle = normalizedAppIdentity(appId(window))
  if (!needle) return null
  var values = entries && typeof entries.slice === "function" ? entries : []
  var best = null
  var bestScore = 0
  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry) continue
    var id = normalizedAppIdentity(entry.id)
    var name = normalizedAppIdentity(entry.name)
    var icon = normalizedAppIdentity(entry.icon)
    var score = 0
    if (needle === id) score = 120
    else if (needle === name || needle === icon) score = 110
    else if (needle.length >= 4 && (id.indexOf(needle) >= 0 || name.indexOf(needle) >= 0 || icon.indexOf(needle) >= 0)) score = 80
    else if (id.length >= 4 && needle.indexOf(id) >= 0) score = 70
    if (score > bestScore) {
      bestScore = score
      best = entry
    }
  }
  return best
}

// Hyprland's focusHistoryID is a rank in the compositor's global focus-history
// list: 0 = currently focused, 1 = most recent before that, ascending = older.
// Transient/popup windows not meaningfully in that history can report null or
// an empty string. Number(null) === 0 and Number("") === 0, so we must guard
// before coercion — otherwise such windows are ranked 0 (treated as current)
// and surface above genuinely recent ones.
function historyRank(window) {
  var ipc = window && window.lastIpcObject ? window.lastIpcObject : {}
  var raw = ipc.focusHistoryID
  if (raw === null || raw === undefined) return 1000000
  // "" and " " both coerce to 0; discard empty/whitespace values (transient
  // windows not meaningfully in the focus history).
  if (typeof raw !== "number" && String(raw).trim() === "") return 1000000
  var rank = Number(raw)
  return isFinite(rank) && rank >= 0 ? rank : 1000000
}

// Addresses arrive as "0x55..." on toplevels but bare "55..." in the
// activewindowv2 event payload; normalise before comparing.
function normalizeAddress(raw) {
  var key = addressKey(raw)
  return key ? "0x" + key : ""
}

function isCurrent(window) {
  return !!(window && window.activated) || historyRank(window) === 0
}

function focusRank(window) {
  return isCurrent(window) ? -1 : historyRank(window)
}

function addressKey(value) {
  var raw = value && typeof value === "object" ? value.address : value
  if (raw === null || raw === undefined) return ""
  var key = String(raw).trim().toLowerCase().replace(/^0x/, "")
  return /^[0-9a-f]+$/.test(key) ? key : ""
}

function promoteAddress(values, address) {
  var key = addressKey(address)
  var source = values && typeof values.slice === "function" ? values : []
  if (!key) return source.slice()
  var result = [key]
  for (var i = 0; i < source.length; i++) {
    var candidate = addressKey(source[i])
    if (candidate && candidate !== key) result.push(candidate)
  }
  return result
}

function addressesByHistory(clients) {
  var source = clients && typeof clients.slice === "function" ? clients.slice() : []
  source.sort(function(left, right) {
    return historyRank({ lastIpcObject: left }) - historyRank({ lastIpcObject: right })
  })
  var result = []
  for (var i = 0; i < source.length; i++) {
    var key = addressKey(source[i])
    if (key && result.indexOf(key) === -1) result.push(key)
  }
  return result
}

// Accept a caller-supplied rank function or authoritative MRU addresses.
function sortedWindows(values, rankFn) {
  var source = values && typeof values.slice === "function" ? values.slice() : []
  var mru = {}
  var order = rankFn && typeof rankFn.slice === "function" ? rankFn : []
  for (var m = 0; m < order.length; m++) mru[addressKey(order[m])] = m
  var decorated = []
  for (var i = 0; i < source.length; i++) {
    var key = addressKey(source[i])
    var rank = typeof rankFn === "function" ? rankFn(source[i]) :
      (key && mru[key] !== undefined ? mru[key] : 1000000 + focusRank(source[i]))
    decorated.push({ value: source[i], index: i, rank: rank })
  }
  decorated.sort(function(left, right) {
    return left.rank - right.rank || left.index - right.index
  })
  var result = []
  for (var j = 0; j < decorated.length; j++) result.push(decorated[j].value)
  return result
}

function filteredWindows(values, query, ocrTextByAddress) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return values.slice()
  return values.filter(function(window) {
    var key = addressKey(window)
    var ocr = key && ocrTextByAddress ? String(ocrTextByAddress[key] || "") : ""
    var metadata = String(window && window.title || "") + " " + appId(window)
    if (window && window.workspace) metadata += " ws " + String(window.workspace.id)
    return (metadata + " " + ocr).toLowerCase().indexOf(q) !== -1
  })
}

// Build the shell command that focuses a window AND moves to its workspace.
// Native toplevel activate does not always switch the visible workspace, so
// the switch is requested explicitly: prefer Omarchy's Lua dispatcher form
// (hl.dsp.focus), fall back to the plain focuswindow syntax for stock
// Hyprland. Returns null when the compositor has not reported an address yet.
function focusCommand(window) {
  var address = normalizeAddress(window && window.address)
  if (!address) return null
  return "hyprctl dispatch \"hl.dsp.focus({ window = 'address:" + address +
    "' })\" >/dev/null 2>&1 || hyprctl dispatch focuswindow \"address:" + address + "\""
}

if (typeof module !== "undefined") module.exports = {
  appId: appId,
  label: label,
  detail: detail,
  windowSnapshot: windowSnapshot,
  windowForAddress: windowForAddress,
  normalizedAppIdentity: normalizedAppIdentity,
  desktopEntryForWindow: desktopEntryForWindow,
  addressKey: addressKey,
  promoteAddress: promoteAddress,
  addressesByHistory: addressesByHistory,
  isCurrent: isCurrent,
  historyRank: historyRank,
  normalizeAddress: normalizeAddress,
  sortedWindows: sortedWindows,
  filteredWindows: filteredWindows,
  focusCommand: focusCommand
}
