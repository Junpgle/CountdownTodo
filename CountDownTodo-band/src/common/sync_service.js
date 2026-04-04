var storage = require('@system.storage')
var interconnect = require('@system.interconnect')
var prompt = require('@system.prompt')

var SYNC_KEY_PREFIX = 'sync_'
var connect = null
var isConnected = false
var batchBuffer = {}
var pendingRequests = {}
var isInitialized = false
var diagMsg = ''

function getConnect() {
  if (!connect) {
    try {
      connect = interconnect.instance()
    } catch (e) {
      diagMsg = 'getConnect err:' + e.message
    }
  }
  return connect
}

function toast(msg) {
  try {
    prompt.showToast({ message: msg, duration: 3000 })
  } catch (e) {}
}

function padZero(num) {
  return num < 10 ? '0' + num : '' + num
}

function flattenArray(arr) {
  var result = []
  var i, j
  for (i = 0; i < arr.length; i++) {
    if (Array.isArray(arr[i])) {
      for (j = 0; j < arr[i].length; j++) {
        result.push(arr[i][j])
      }
    } else {
      result.push(arr[i])
    }
  }
  return result
}

function logDebug(msg) {
  diagMsg = msg
}

function saveLocalData(type, data, callback) {
  storage.set({
    key: SYNC_KEY_PREFIX + type,
    value: JSON.stringify(data),
    success: function() { if (callback) callback(true) },
    fail: function(err) { if (callback) callback(false) }
  })
}

function adaptItem(type, item) {
  var adapted = {}
  var key
  for (key in item) {
    if (item.hasOwnProperty(key)) {
      adapted[key] = item[key]
    }
  }
  if (type === 'countdown') {
    if (adapted.target_time && !adapted.targetDate) { adapted.targetDate = adapted.target_time }
    if (!adapted.title && adapted.name) { adapted.title = adapted.name }
  } else if (type === 'todo') {
    if (adapted.content && !adapted.title) { adapted.title = adapted.content }
    adapted.status = (adapted.is_completed === 1 || adapted.is_completed === true) ? 'done' : 'undone'
    if (adapted.created_date && !adapted.startDate) { adapted.startDate = adapted.created_date }
    if (adapted.due_date && !adapted.endDate) { adapted.endDate = adapted.due_date }
    if (adapted.remark !== undefined && !adapted.description) { adapted.description = adapted.remark }
  } else if (type === 'course') {
    if (adapted.courseName && !adapted.name) { adapted.name = adapted.courseName }
    if (adapted.roomName && !adapted.location) { adapted.location = adapted.roomName }
    if (adapted.teacherName && !adapted.teacher) { adapted.teacher = adapted.teacherName }
    if (typeof adapted.startTime === 'number') {
      adapted.startTime = padZero(Math.floor(adapted.startTime / 100)) + ':' + padZero(adapted.startTime % 100)
    }
    if (typeof adapted.endTime === 'number') {
      adapted.endTime = padZero(Math.floor(adapted.endTime / 100)) + ':' + padZero(adapted.endTime % 100)
    }
  } else if (type === 'pomodoro') {
    if (adapted.todo_title && !adapted.todoTitle) { adapted.todoTitle = adapted.todo_title }
    if (adapted.tag_uuids && !adapted.tagUuids) { adapted.tagUuids = adapted.tag_uuids }
    if (adapted.tag_names && !adapted.tagNames) { adapted.tagNames = adapted.tag_names }
    if (adapted.planned_duration && !adapted.plannedDuration) { adapted.plannedDuration = adapted.planned_duration }
    if (adapted.start_time && !adapted.startTime) { adapted.startTime = adapted.start_time }
    if (adapted.end_time && !adapted.endTime) { adapted.endTime = adapted.end_time }
    if (adapted.target_end_ms && !adapted.targetEndMs) { adapted.targetEndMs = adapted.target_end_ms }
    if (adapted.session_uuid && !adapted.sessionUuid) { adapted.sessionUuid = adapted.session_uuid }
    if (adapted.is_count_up !== undefined && !adapted.isCountUp) { adapted.isCountUp = adapted.is_count_up }
    if (adapted.mode !== undefined && !adapted.mode) { adapted.mode = adapted.mode }
  }
  return adapted
}

function resolveRequest(type, result) {
  if (pendingRequests[type]) {
    if (pendingRequests[type].timeout) {
      clearTimeout(pendingRequests[type].timeout)
    }
    if (pendingRequests[type].callback) {
      pendingRequests[type].callback(result)
    }
    delete pendingRequests[type]
  }
}

function replacePhoneData(type, phoneData) {
  if (!Array.isArray(phoneData)) {
    saveLocalData(type, phoneData, null)
    resolveRequest(type, { success: true, message: '已同步手机数据' })
    return
  }
  var validItems = []
  var i
  for (i = 0; i < phoneData.length; i++) {
    if (!(phoneData[i].is_deleted === 1 || phoneData[i].is_deleted === true)) {
      validItems.push(adaptItem(type, phoneData[i]))
    }
  }
  saveLocalData(type, validItems, null)
  resolveRequest(type, { success: true, message: '已同步 (' + validItems.length + '条)' })
}

function handleReceivedData(data) {
  try {
    var parsedData = null
    if (typeof data === 'object' && data !== null && data.type) {
      parsedData = data
    } else if (typeof data === 'string') {
      parsedData = JSON.parse(data)
    } else if (typeof data === 'object' && data !== null && data.data !== undefined) {
      var innerData = data.data
      if (typeof innerData === 'string') {
        parsedData = JSON.parse(innerData)
      } else if (typeof innerData === 'object') {
        parsedData = innerData
      }
    }
    if (!parsedData || !parsedData.type) { return }

    var type = parsedData.type
    var batchData = parsedData.data
    var batchNum = parsedData.batchNum || 1
    var totalBatches = parsedData.totalBatches || 1

    if (totalBatches === 1) {
      replacePhoneData(type, batchData)
      return
    }

    if (!batchBuffer[type]) {
      batchBuffer[type] = { batches: [], totalBatches: totalBatches, timeout: null }
    }
    var buffer = batchBuffer[type]
    buffer.totalBatches = totalBatches
    buffer.batches[batchNum - 1] = batchData

    var receivedCount = 0
    var k
    for (k = 0; k < buffer.batches.length; k++) {
      if (buffer.batches[k] !== undefined) { receivedCount++ }
    }

    if (receivedCount >= buffer.totalBatches) {
      replacePhoneData(type, flattenArray(buffer.batches))
      delete batchBuffer[type]
    } else {
      if (buffer.timeout) clearTimeout(buffer.timeout)
      buffer.timeout = setTimeout(function() {
        var collectedData = []
        var a, b
        for (a = 0; a < buffer.batches.length; a++) {
          if (buffer.batches[a] !== undefined) {
            if (Array.isArray(buffer.batches[a])) {
              for (b = 0; b < buffer.batches[a].length; b++) { collectedData.push(buffer.batches[a][b]) }
            } else {
              collectedData.push(buffer.batches[a])
            }
          }
        }
        replacePhoneData(type, collectedData)
        delete batchBuffer[type]
      }, 10000)
    }
  } catch (error) {
    logDebug('Handle error: ' + error.message)
  }
}

function doSend(type, callback) {
  var conn = getConnect()
  if (!conn) {
    callback(false)
    return
  }
  if (typeof conn.send !== 'function') {
    callback(false)
    return
  }
  conn.send({
    data: { type: type, action: 'request_sync', timestamp: Date.now() },
    success: function() {
      callback(true)
    },
    fail: function(err, code) {
      callback(false)
    }
  })
}

function requestSyncFromPhone(type, onResult) {
  var conn = getConnect()
  if (!conn) {
    if (onResult) onResult({ success: false, message: '未连接到手机App' })
    return
  }
  if (typeof conn.send !== 'function') {
    if (onResult) onResult({ success: false, message: '连接异常' })
    return
  }

  var timeoutId = setTimeout(function() {
    resolveRequest(type, { success: false, message: '手机未响应' })
  }, 8000)

  pendingRequests[type] = { callback: onResult, timeout: timeoutId }

  doSend(type, function(sent) {
    if (!sent) {
      resolveRequest(type, { success: false, message: '发送失败' })
    }
  })
}

function init() {
  if (isInitialized && connect) {
    return
  }
  try {
    var instance = interconnect.instance()
    if (instance) {
      connect = instance
      var hasSend = typeof connect.send === 'function'
      var hasGRS = typeof connect.getReadyState === 'function'
      diagMsg = 'init:send=' + hasSend + ' grs=' + hasGRS
      connect.onopen = function(data) {
        isConnected = true
        sendVersionInfo()
      }
      connect.onclose = function(data) {
        isConnected = false
      }
      connect.onerror = function(data) {
        isConnected = false
      }
      connect.onmessage = function(data) {
        handleReceivedData(data)
      }

      if (hasGRS) {
        connect.getReadyState({
          success: function(data) {
            var status = data ? data.status : -1
            if (status === 1) {
              isConnected = true
              sendVersionInfo()
            }
          },
          fail: function() {}
        })
      }

      isInitialized = true
    }
  } catch (e) {
    diagMsg = 'init err:' + e.message
  }
}

function destroy() {
  var type, buffer
  for (type in batchBuffer) {
    buffer = batchBuffer[type]
    if (buffer.timeout) { clearTimeout(buffer.timeout); buffer.timeout = null }
  }
  batchBuffer = {}
  for (type in pendingRequests) {
    if (pendingRequests[type].timeout) {
      clearTimeout(pendingRequests[type].timeout)
    }
  }
  pendingRequests = {}
  connect = null
  isConnected = false
  isInitialized = false
}

function sendVersionInfo() {
  var conn = getConnect()
  if (!conn) return
  if (typeof conn.send !== 'function') return
  conn.send({
    data: { type: 'band_info', version: '1.0.0', version_code: 1, timestamp: Date.now() },
    success: function() {},
    fail: function() {}
  })
}

function sendDebugLog(message) {
  var conn = getConnect()
  if (!conn) return
  if (typeof conn.send !== 'function') return
  conn.send({
    data: { type: 'debug', message: message, timestamp: Date.now() },
    success: function() {},
    fail: function() {}
  })
}

function getDiagMsg() {
  return diagMsg
}

function syncTodo(onResult) {
  requestSyncFromPhone('todo', onResult)
}

function syncCourse(onResult) {
  requestSyncFromPhone('course', onResult)
}

function syncCountdown(onResult) {
  requestSyncFromPhone('countdown', onResult)
}

function syncPomodoro(onResult) {
  requestSyncFromPhone('pomodoro', onResult)
}

function syncAll(onResult) {
  var results = {}
  var completed = 0
  var total = 4

  function checkDone() {
    completed++
    if (completed >= total && onResult) {
      onResult(results)
    }
  }

  syncTodo(function(r) {
    results.todo = r
    checkDone()
  })
  syncCourse(function(r) {
    results.course = r
    checkDone()
  })
  syncCountdown(function(r) {
    results.countdown = r
    checkDone()
  })
  syncPomodoro(function(r) {
    results.pomodoro = r
    checkDone()
  })
}

module.exports = {
  init: init,
  destroy: destroy,
  handleReceivedData: handleReceivedData,
  adaptItem: adaptItem,
  saveLocalData: saveLocalData,
  requestSyncFromPhone: requestSyncFromPhone,
  syncAll: syncAll,
  sendVersionInfo: sendVersionInfo,
  sendDebugLog: sendDebugLog,
  syncTodo: syncTodo,
  syncCourse: syncCourse,
  syncCountdown: syncCountdown,
  syncPomodoro: syncPomodoro,
  getDiagMsg: getDiagMsg
}