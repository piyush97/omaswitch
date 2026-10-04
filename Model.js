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
  if (raw === null || raw === undefined) return ""
  var value = String(raw).trim()
  if (value === "") return ""
  return value.indexOf("0x") === 0 ? value : "0x" + value
}

function isCurrent(window) {
  return !!(window && window.activated) || historyRank(window) === 0
}

function focusRank(window) {
  return isCurrent(window) ? -1 : historyRank(window)
}

// rankFn lets the caller supply a more reliable order than focusRank; see the
// mru notes in Switcher.qml. Defaults to focusRank so the model stays usable
// (and testable) on its own.
function sortedWindows(values, rankFn) {
  var source = values && typeof values.slice === "function" ? values.slice() : []
  var rank = typeof rankFn === "function" ? rankFn : focusRank
  var decorated = []
  for (var i = 0; i < source.length; i++) decorated.push({ value: source[i], index: i })
  decorated.sort(function(left, right) {
    return rank(left.value) - rank(right.value) || left.index - right.index
  })
  var result = []
  for (var j = 0; j < decorated.length; j++) result.push(decorated[j].value)
  return result
}

function filteredWindows(values, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return values.slice()
  return values.filter(function(window) {
    return (label(window) + " " + detail(window)).toLowerCase().indexOf(q) !== -1
  })
}

// Build the shell command that focuses a window AND moves to its workspace.
// Native toplevel activate does not always switch the visible workspace, so
// the switch is requested explicitly: prefer Omarchy's Lua dispatcher form
// (hl.dsp.focus), fall back to the plain focuswindow syntax for stock
// Hyprland. Returns null when the window has no address, deferring to the
// native activate path in Switcher.qml.
function focusCommand(window) {
  var raw = window && window.address
  if (raw === null || raw === undefined || raw === "") return null
  var rawAddress = String(raw)
  var address = rawAddress.indexOf("0x") === 0 ? rawAddress : "0x" + rawAddress
  return "hyprctl dispatch \"hl.dsp.focus({ window = 'address:" + address +
    "' })\" >/dev/null 2>&1 || hyprctl dispatch focuswindow \"address:" + address + "\""
}

if (typeof module !== "undefined") module.exports = {
  appId: appId,
  label: label,
  detail: detail,
  normalizedAppIdentity: normalizedAppIdentity,
  desktopEntryForWindow: desktopEntryForWindow,
  isCurrent: isCurrent,
  historyRank: historyRank,
  normalizeAddress: normalizeAddress,
  sortedWindows: sortedWindows,
  filteredWindows: filteredWindows,
  focusCommand: focusCommand
}
