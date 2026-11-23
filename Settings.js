var defaults = {
  scope: "all",
  groupByWorkspace: true,
  livePreview: true,
  contentSearch: true,
  setupDismissed: false
}

var scopes = ["all", "workspace", "monitor"]

function read(entry) {
  var result = {}
  var source = entry && typeof entry === "object" ? entry : {}

  // scope: must be one of the allowed scopes
  var scope = source.scope
  result.scope = typeof scope === "string" && scopes.indexOf(scope) !== -1 ? scope : defaults.scope

  // groupByWorkspace: must be boolean
  var groupByWorkspace = source.groupByWorkspace
  result.groupByWorkspace = typeof groupByWorkspace === "boolean" ? groupByWorkspace : defaults.groupByWorkspace

  // livePreview: must be boolean
  var livePreview = source.livePreview
  result.livePreview = typeof livePreview === "boolean" ? livePreview : defaults.livePreview

  // contentSearch: must be boolean
  var contentSearch = source.contentSearch
  result.contentSearch = typeof contentSearch === "boolean" ? contentSearch : defaults.contentSearch

  // setupDismissed: must be boolean
  var setupDismissed = source.setupDismissed
  result.setupDismissed = typeof setupDismissed === "boolean" ? setupDismissed : defaults.setupDismissed

  return result
}

function patch(entry, key, value) {
  // key must be known
  if (!defaults.hasOwnProperty(key)) return null

  // validate the value
  var valid = false
  if (key === "scope") {
    valid = typeof value === "string" && scopes.indexOf(value) !== -1
  } else {
    // groupByWorkspace, livePreview, contentSearch, setupDismissed must be boolean
    valid = typeof value === "boolean"
  }

  if (!valid) return null

  // copy entry and remove id, then set the key
  var result = {}
  var source = entry && typeof entry === "object" ? entry : {}
  for (var k in source) {
    if (k !== "id") {
      result[k] = source[k]
    }
  }
  result[key] = value

  return result
}

if (typeof module !== "undefined") module.exports = {
  defaults: defaults,
  scopes: scopes,
  read: read,
  patch: patch
}
