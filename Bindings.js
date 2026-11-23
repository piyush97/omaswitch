var BEGIN = "-- OmaSwitch begin"
var END = "-- OmaSwitch end"

function block() {
  return BEGIN + "\n" +
    'hl.unbind("ALT + TAB")\n' +
    'hl.unbind("ALT + SHIFT + TAB")\n' +
    'hl.unbind("ALT + GRAVE")\n' +
    'o.bind("ALT + TAB", "OmaSwitch", "omarchy-shell shell summon piyush.omaswitch \'{\\\"mode\\\":\\\"cycle\\\",\\\"direction\\\":1}\'\")\n' +
    'o.bind("ALT + SHIFT + TAB", "OmaSwitch (reverse)", "omarchy-shell shell summon piyush.omaswitch \'{\\\"mode\\\":\\\"cycle\\\",\\\"direction\\\":-1}\'\")\n' +
    'o.bind("ALT + GRAVE", "OmaSwitch (same app)", "omarchy-shell shell summon piyush.omaswitch \'{\\\"mode\\\":\\\"cycle\\\",\\\"scope\\\":\\\"app\\\",\\\"direction\\\":1}\'\")\n' +
    END
}

function state(text) {
  var handWritten = false
  var hasAppScope = false

  var lines = text.split(/\r?\n/)
  var beginIdx = -1
  var endIdx = -1

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === BEGIN) {
      beginIdx = i
      break
    }
  }

  if (beginIdx !== -1) {
    for (var i = beginIdx + 1; i < lines.length; i++) {
      if (lines[i].trim() === END) {
        endIdx = i
        break
      }
    }
  }

  // managed = BEGIN followed by END (not END before BEGIN, not only BEGIN)
  var managed = beginIdx !== -1 && endIdx !== -1 && beginIdx < endIdx

  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].replace(/^\s+|\s+$/g, "")

    // Skip comment lines
    if (trimmed.indexOf("--") === 0) {
      continue
    }

    // Skip lines inside managed block (only when validated)
    if (managed && i >= beginIdx && i <= endIdx) {
      continue
    }

    // Check for hand-written reference
    if (trimmed.indexOf("piyush.omaswitch") !== -1) {
      handWritten = true
    }
  }

  // Check for app scope in any non-comment line
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].replace(/^\s+|\s+$/g, "")
    if (trimmed.indexOf("--") === 0) {
      continue
    }
    if (trimmed.indexOf('"scope":"app"') !== -1 || trimmed.indexOf('\\"scope\\":\\"app\\"') !== -1) {
      hasAppScope = true
      break
    }
  }

  return {
    managed: managed,
    handWritten: handWritten,
    hasAppScope: hasAppScope
  }
}

function needsSetup(text) {
  var st = state(text)
  return !st.managed && !st.handWritten
}

function detectLineEnding(text) {
  if (text.indexOf("\r\n") !== -1) {
    return "\r\n"
  }
  return "\n"
}

function appendBlock(text) {
  var st = state(text)
  if (st.managed) {
    return text
  }

  var lineEnding = detectLineEnding(text)
  var needsTrailing = text.length === 0 || text[text.length - 1] !== "\n"

  var result = text
  if (needsTrailing) {
    result += lineEnding
  }

  // Ensure exactly one blank line before the block
  result += lineEnding

  // Add the block with detected line ending
  var blockLines = block().split("\n")
  for (var i = 0; i < blockLines.length; i++) {
    result += blockLines[i]
    if (i < blockLines.length - 1) {
      result += lineEnding
    }
  }

  // Ensure trailing newline
  result += lineEnding

  return result
}

function stripBlock(text) {
  var st = state(text)
  if (!st.managed) {
    return text
  }

  var lineEnding = detectLineEnding(text)
  var lines = text.split(/\r?\n/)

  var beginIdx = -1
  var endIdx = -1

  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() === BEGIN) {
      beginIdx = i
      break
    }
  }

  if (beginIdx !== -1) {
    for (var i = beginIdx + 1; i < lines.length; i++) {
      if (lines[i].trim() === END) {
        endIdx = i
        break
      }
    }
  }

  if (beginIdx === -1 || endIdx === -1 || beginIdx >= endIdx) {
    return text
  }

  // Check if line before BEGIN is blank
  var lineBeforeIdx = beginIdx - 1
  var shouldDropLineBefore = false
  if (lineBeforeIdx >= 0) {
    var lineBefore = lines[lineBeforeIdx].replace(/^\s+|\s+$/g, "")
    shouldDropLineBefore = lineBefore === ""
  }

  // Remove block and the blank line before it (only if blank)
  var before = shouldDropLineBefore ? lines.slice(0, lineBeforeIdx) : lines.slice(0, beginIdx)
  var after = lines.slice(endIdx + 1)

  var result = before.concat(after).join(lineEnding)

  // Ensure trailing newline
  if (result.length > 0 && result[result.length - 1] !== "\n") {
    result += lineEnding
  }

  return result
}

function newErrors(before, after) {
  var beforeLines = before.split("\n").map(function(l) {
    return l.replace(/^\s+|\s+$/g, "")
  }).filter(function(l) {
    return l.length > 0
  })

  var afterLines = after.split("\n").map(function(l) {
    return l.replace(/^\s+|\s+$/g, "")
  }).filter(function(l) {
    return l.length > 0
  })

  var result = []
  for (var i = 0; i < afterLines.length; i++) {
    var found = false
    for (var j = 0; j < beforeLines.length; j++) {
      if (afterLines[i] === beforeLines[j]) {
        found = true
        break
      }
    }
    if (!found) {
      result.push(afterLines[i])
    }
  }

  return result
}

function appScopeLine() {
  var lines = block().split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].indexOf('o.bind("ALT + GRAVE"') === 0) {
      return lines[i]
    }
  }
  return ""
}

if (typeof module !== "undefined") module.exports = {
  BEGIN: BEGIN,
  END: END,
  block: block,
  state: state,
  needsSetup: needsSetup,
  appendBlock: appendBlock,
  stripBlock: stripBlock,
  newErrors: newErrors,
  appScopeLine: appScopeLine
}
