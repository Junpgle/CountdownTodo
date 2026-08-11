function padZero(num) {
  return num < 10 ? '0' + num : '' + num
}

function parseJson(value, fallback) {
  if (value === null || value === undefined || value === '') {
    return fallback
  }
  try {
    return JSON.parse(value)
  } catch (e) {
    return fallback
  }
}

function parseJsonArray(value) {
  var parsed = parseJson(value, [])
  return Array.isArray(parsed) ? parsed : []
}

module.exports = {
  padZero: padZero,
  parseJson: parseJson,
  parseJsonArray: parseJsonArray
}
