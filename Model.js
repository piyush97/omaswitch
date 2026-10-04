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
    return metadataMatches(window, q) || ocrText(ocrTextByAddress, window).toLowerCase().indexOf(q) !== -1
  })
}

function metadataMatches(window, q) {
  var metadata = String(window && window.title || "") + " " + appId(window)
  if (window && window.workspace) metadata += " ws " + String(window.workspace.id)
  return metadata.toLowerCase().indexOf(q) !== -1
}

function ocrEntry(ocrByAddress, window) {
  var key = addressKey(window)
  return key && ocrByAddress ? ocrByAddress[key] : null
}

function ocrText(ocrByAddress, window) {
  var entry = ocrEntry(ocrByAddress, window)
  return entry ? String(typeof entry === "string" ? entry : entry.text || "") : ""
}

// Parse `tesseract ... tsv`: Tesseract's page layout analysis groups words into
// block/paragraph/line; boxes are normalised to 0..1 of the captured image.
function parseOcrTsv(tsv) {
  var rows = String(tsv || "").split("\n")
  var pageW = 0, pageH = 0, words = 0
  var lines = {}, order = []
  for (var i = 1; i < rows.length && words < 4000; i++) {
    var c = rows[i].split("	")
    if (c.length < 12) continue
    var level = Number(c[0])
    if (level === 1) { pageW = Number(c[8]); pageH = Number(c[9]); continue }
    var word = c.slice(11).join("\t").trim()
    if (level !== 5 || !word || !(pageW > 0) || !(pageH > 0)) continue
    var id = c[2] + "." + c[3] + "." + c[4]
    if (!lines[id]) { lines[id] = []; order.push(id) }
    lines[id].push({ text: word, x: Number(c[6]) / pageW, y: Number(c[7]) / pageH,
                     w: Number(c[8]) / pageW, h: Number(c[9]) / pageH })
    words++
  }
  var result = order.map(function(id) { return lines[id] })
  var text = result.map(function(line) {
    return line.map(function(w) { return w.text }).join(" ")
  }).join("\n")
  return { text: text.slice(0, 12000), lines: result }
}

// Boxes for OCR-only matches; metadata matches already explain themselves.
function ocrHighlights(window, query, ocrByAddress) {
  var q = String(query || "").trim().toLowerCase()
  var entry = ocrEntry(ocrByAddress, window)
  if (!q || !entry || !entry.lines || metadataMatches(window, q)) return []
  var boxes = []
  for (var i = 0; i < entry.lines.length && boxes.length < 24; i++) {
    var line = entry.lines[i], text = "", spans = []
    for (var j = 0; j < line.length; j++) {
      if (j) text += " "
      spans.push({ start: text.length, end: text.length + line[j].text.length })
      text += line[j].text
    }
    var lower = text.toLowerCase()
    for (var at = lower.indexOf(q); at !== -1 && boxes.length < 24; at = lower.indexOf(q, at + q.length)) {
      var x1 = 1, y1 = 1, x2 = 0, y2 = 0
      for (var k = 0; k < line.length; k++) {
        if (spans[k].end <= at || spans[k].start >= at + q.length) continue
        x1 = Math.min(x1, line[k].x); y1 = Math.min(y1, line[k].y)
        x2 = Math.max(x2, line[k].x + line[k].w); y2 = Math.max(y2, line[k].y + line[k].h)
      }
      if (x2 > x1 && y2 > y1) boxes.push({ x: x1, y: y1, w: x2 - x1, h: y2 - y1 })
    }
  }
  return boxes
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
  parseOcrTsv: parseOcrTsv,
  ocrHighlights: ocrHighlights,
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
