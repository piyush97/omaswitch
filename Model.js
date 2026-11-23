var maxDisplayLength = 160

function boundedText(value) {
  value = String(value || "")
  if (value.length <= maxDisplayLength) return value
  var end = maxDisplayLength - 1
  // Do not cut an emoji or other astral character in half.
  var last = value.charCodeAt(end - 1)
  if (last >= 0xd800 && last <= 0xdbff) end--
  return value.slice(0, end) + "…"
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
    monitor: window.monitor ? { name: String(window.monitor.name || "") }
      : window.workspace && window.workspace.monitor ? { name: String(window.workspace.monitor.name || "") } : null,
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

// Quickshell creates a toplevel for any title/focus/urgent event naming an
// unknown address and only drops it on `closewindow`, so windows that never
// got `openwindow` (or events racing a close) linger as workspace-less ghosts.
// Every window Hyprland actually manages has a workspace.
function managedWindows(values) {
  var source = values && typeof values.filter === "function" ? values : []
  return source.filter(function(window) { return !!(window && window.workspace) })
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
    // Lowercase per word before measuring spans: toLowerCase() can change
    // length (for example "İ" becomes two code units), which would shift
    // every later span away from the match index.
    var line = entry.lines[i], lower = "", spans = []
    for (var j = 0; j < line.length; j++) {
      if (j) lower += " "
      var word = line[j].text.toLowerCase()
      spans.push({ start: lower.length, end: lower.length + word.length })
      lower += word
    }
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
// Hyprland. Lua hl.dsp.focus does not raise, so a floating window could gain
// focus while staying behind others; raise it as a click would.
// Returns null when the compositor has not reported an address yet.
function focusCommand(window) {
  var address = normalizeAddress(window && window.address)
  if (!address) return null
  var selector = "window = 'address:" + address + "'"
  return "if hyprctl dispatch \"hl.dsp.focus({ " + selector + " })\" >/dev/null 2>&1; then " +
    "hyprctl dispatch \"hl.dsp.window.alter_zorder({ mode = 'top', " + selector + " })\"; " +
    "else hyprctl dispatch focuswindow \"address:" + address + "\"; fi"
}

// Filter windows by scope: "all" (no filtering), "workspace" (match ctx.workspaceId),
// "monitor" (match ctx.monitorName, trying window.monitor.name then window.workspace.monitor.name).
function scopedWindows(windows, scope, ctx) {
  var source = windows && typeof windows.filter === "function" ? windows : []
  if (scope === "all") return source
  if (scope === "workspace") {
    var targetId = ctx && ctx.workspaceId
    return source.filter(function(w) {
      return w && w.workspace && w.workspace.id === targetId
    })
  }
  if (scope === "monitor") {
    var targetName = ctx && ctx.monitorName
    return source.filter(function(w) {
      var monName = w && w.monitor && w.monitor.name
      if (!monName && w && w.workspace && w.workspace.monitor) {
        monName = w.workspace.monitor.name
      }
      return monName === targetName
    })
  }
  return source
}

// Match case-insensitive query in label(window), returning { before, match, after } or null.
// Uses same Unicode-safe lowercasing as matchSnippet/ocrHighlights so indices map to original.
function titleMatch(window, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return null
  var title = label(window)
  var idx = title.toLowerCase().indexOf(q)
  if (idx === -1) return null
  return {
    before: title.substring(0, idx),
    match: title.substring(idx, idx + q.length),
    after: title.substring(idx + q.length)
  }
}

// Build rows for display: headers (kind: "header", workspaceId, label) and windows
// (kind: "window", window, jump). jump is 1..9 for the first nine window rows, null after.
// When opts.group is true, group windows by workspace with headers.
function displayRows(windows, opts) {
  var source = windows && typeof windows.slice === "function" ? windows : []
  var group = opts && opts.group
  var rows = []
  var jumpCounter = 1
  if (!group) {
    for (var i = 0; i < source.length; i++) {
      rows.push({
        kind: "window",
        window: source[i],
        jump: jumpCounter <= 9 ? jumpCounter : null
      })
      jumpCounter++
    }
    return rows
  }
  // Grouped: collect windows per workspace, emit in order first seen
  var byWorkspace = {}
  var order = []
  for (var j = 0; j < source.length; j++) {
    var w = source[j]
    var wsId = w && w.workspace && w.workspace.id
    if (wsId == null) continue
    if (!byWorkspace[wsId]) {
      byWorkspace[wsId] = []
      order.push(wsId)
    }
    byWorkspace[wsId].push(w)
  }
  for (var k = 0; k < order.length; k++) {
    var id = order[k]
    var wsWindows = byWorkspace[id]
    if (wsWindows.length === 0) continue
    var headerLabel = "Workspace " + id
    if (id < 0 || (wsWindows[0].workspace.name && wsWindows[0].workspace.name.indexOf("special") !== -1)) {
      headerLabel = "Special " + (wsWindows[0].workspace.name || id)
    }
    rows.push({ kind: "header", workspaceId: id, label: headerLabel })
    for (var m = 0; m < wsWindows.length; m++) {
      rows.push({
        kind: "window",
        window: wsWindows[m],
        jump: jumpCounter <= 9 ? jumpCounter : null
      })
      jumpCounter++
    }
  }
  return rows
}

// Find the row index where jump === n, or -1.
function windowRowIndex(rows, n) {
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window" && rows[i].jump === n) return i
  }
  return -1
}

// Step from rows[currentIndex] by delta, skipping headers. Wraps around. Returns -1 if no window rows.
function stepWindowRow(rows, currentIndex, delta) {
  var windows = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window") windows.push(i)
  }
  if (windows.length === 0) return -1
  var pos = windows.indexOf(currentIndex)
  if (pos === -1) pos = 0
  var next = (pos + delta) % windows.length
  if (next < 0) next += windows.length
  return windows[next]
}

// Clamp index to nearest window row or -1 if none.
function clampSelection(rows, index) {
  var windows = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window") windows.push(i)
  }
  if (windows.length === 0) return -1
  if (index < 0) return windows[0]
  for (var j = index; j < rows.length; j++) {
    if (rows[j] && rows[j].kind === "window") return j
  }
  for (var k = index; k >= 0; k--) {
    if (rows[k] && rows[k].kind === "window") return k
  }
  return windows[windows.length - 1]
}

// Return { before, match, after } snippet for OCR-only matches, or null.
// Centers match; trims at word boundaries; adds … on trimmed sides; total ≤ maxLength.
// Never splits surrogate pairs.
function matchSnippet(window, query, ocrByAddress, maxLength) {
  var q = String(query || "").trim().toLowerCase()
  if (!q || metadataMatches(window, q)) return null
  var text = ocrText(ocrByAddress, window)
  if (!text) return null
  var entry = ocrEntry(ocrByAddress, window)
  if (!entry) return null
  var original = text
  var lower = text.toLowerCase()
  // Handle layout objects with per-word lowercasing
  if (entry.lines && typeof entry.lines === "object" && entry.lines.length) {
    // Build lowercased text per-word to find match index without shifting
    lower = ""
    var spans = []
    for (var lineIdx = 0; lineIdx < entry.lines.length; lineIdx++) {
      var line = entry.lines[lineIdx]
      for (var wordIdx = 0; wordIdx < line.length; wordIdx++) {
        if (lower && lower[lower.length - 1] !== "\n") lower += " "
        var word = line[wordIdx].text.toLowerCase()
        spans.push({ start: lower.length, end: lower.length + word.length, orig: line[wordIdx].text })
        lower += word
      }
      if (lineIdx < entry.lines.length - 1) lower += "\n"
    }
    // Reconstruct original from spans
    original = ""
    for (var s = 0; s < spans.length; s++) {
      original += spans[s].orig
      if (s < spans.length - 1 && spans[s + 1].start > spans[s].end) original += " "
    }
  }
  var idx = lower.indexOf(q)
  if (idx === -1) return null
  var matchStart = idx
  var matchEnd = idx + q.length
  var ellipsis = "…"
  // The match itself occupies matchEnd - matchStart chars in original.
  // Total budget: maxLength. Reserve space for match + potential ellipses.
  var matchLen = matchEnd - matchStart
  var availableForContext = maxLength - matchLen
  var ellipsisNeededBefore = matchStart > 0
  var ellipsisNeededAfter = matchEnd < original.length
  if (ellipsisNeededBefore) availableForContext -= ellipsis.length
  if (ellipsisNeededAfter) availableForContext -= ellipsis.length
  if (availableForContext < 0) availableForContext = 0
  var beforeBudget = Math.floor(availableForContext / 2)
  var afterBudget = availableForContext - beforeBudget
  var beforeStart = Math.max(0, matchStart - beforeBudget)
  var afterEnd = Math.min(original.length, matchEnd + afterBudget)
  // Trim to word boundaries
  while (beforeStart > 0 && beforeStart < matchStart && !/\s/.test(original[beforeStart - 1])) beforeStart--
  while (afterEnd < original.length && afterEnd > matchEnd && !/\s/.test(original[afterEnd])) afterEnd++
  var before = original.substring(beforeStart, matchStart)
  var match = original.substring(matchStart, matchEnd)
  var after = original.substring(matchEnd, afterEnd)
  // Add ellipsis
  if (beforeStart > 0) before = ellipsis + before.trimStart()
  if (afterEnd < original.length) after = after.trimEnd() + ellipsis
  // Ensure no surrogate splits
  function isSurrogate(str, idx) {
    if (idx < 0 || idx >= str.length) return false
    var code = str.charCodeAt(idx)
    return code >= 0xD800 && code <= 0xDFFF
  }
  if (before && isSurrogate(before, before.length - 1)) before = before.slice(0, -1)
  if (match && isSurrogate(match, 0)) match = match.slice(1)
  if (match && isSurrogate(match, match.length - 1)) match = match.slice(0, -1)
  if (after && isSurrogate(after, 0)) after = after.slice(1)
  // Final enforcement: truncate if total exceeds maxLength
  var total = before.length + match.length + after.length
  if (total > maxLength) {
    var excess = total - maxLength
    // Try trimming after first
    if (after.length >= excess) {
      after = after.substring(0, after.length - excess)
      if (after && isSurrogate(after, after.length - 1)) after = after.slice(0, -1)
    } else {
      after = ""
      excess -= after.length
      if (before.length >= excess) {
        before = before.substring(excess)
        if (before && isSurrogate(before, 0)) before = before.slice(1)
      } else {
        before = ""
      }
    }
  }
  return { before: before, match: match, after: after }
}

// Find next window row (wrapping) with same appId as rows[currentRowIndex].window.
// Returns row index or currentRowIndex if no other app match.
function appCycleIndex(rows, currentRowIndex, direction) {
  if (!rows[currentRowIndex] || rows[currentRowIndex].kind !== "window") return currentRowIndex
  var current = rows[currentRowIndex].window
  var targetId = appId(current)
  if (!targetId) return currentRowIndex
  var windows = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].kind === "window" && appId(rows[i].window) === targetId) windows.push(i)
  }
  if (windows.length <= 1) return currentRowIndex
  var pos = windows.indexOf(currentRowIndex)
  if (pos === -1) return currentRowIndex
  var next = (pos + direction) % windows.length
  if (next < 0) next += windows.length
  return windows[next]
}

// Return Lua dispatch command to move window to workspaceId, or null if already there or no address.
function moveHereLua(window, workspaceId) {
  var address = normalizeAddress(window && window.address)
  if (!address || !/^0x[0-9a-fA-F]+$/.test(address)) return null
  var currentWs = window && window.workspace && window.workspace.id
  if (!Number.isSafeInteger(workspaceId) || currentWs === workspaceId) return null
  return "(function() hl.dispatch(hl.dsp.window.move({ workspace = '" + workspaceId + "', follow = false, window = 'address:" + address + "' })) end)"
}

// Return normalized address for closewindow, or null.
function closeTarget(window) {
  var address = normalizeAddress(window && window.address)
  if (!address || !/^0x[0-9a-fA-F]+$/.test(address)) return null
  return address
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
  managedWindows: managedWindows,
  sortedWindows: sortedWindows,
  filteredWindows: filteredWindows,
  focusCommand: focusCommand,
  scopedWindows: scopedWindows,
  titleMatch: titleMatch,
  displayRows: displayRows,
  windowRowIndex: windowRowIndex,
  stepWindowRow: stepWindowRow,
  clampSelection: clampSelection,
  matchSnippet: matchSnippet,
  appCycleIndex: appCycleIndex,
  moveHereLua: moveHereLua,
  closeTarget: closeTarget
}
