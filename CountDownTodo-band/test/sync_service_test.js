var assert = require('assert')
var fs = require('fs')
var path = require('path')
var vm = require('vm')

var source = fs.readFileSync(path.join(__dirname, '../src/common/sync_service.js'), 'utf8')

function createHarness(options) {
  options = options || {}
  var now = 0
  var nextTimerId = 1
  var timers = {}
  var initialTodos = [{ id: 'old-1' }, { id: 'old-2' }]
  var saved = { sync_todo: JSON.stringify(initialTodos) }
  var writes = 0
  var sent = []
  var connection = {
    send: function(request) {
      sent.push(request.data)
      request.success()
    }
  }
  var storage = {
    set: function(request) {
      if (options.failStorage) {
        if (request.fail) request.fail(new Error('storage failed'))
        return
      }
      saved[request.key] = request.value
      writes++
      if (request.success) request.success()
    },
    delete: function(request) {
      delete saved[request.key]
      if (request.success) request.success()
    }
  }
  var module = { exports: {} }
  var context = {
    module: module,
    require: function(name) {
      if (name === '@system.storage') return storage
      if (name === '@system.interconnect') return { instance: function() { return connection } }
      if (name === '@system.app') return { getInfo: function() {} }
      if (name === '@system.router') return {}
      if (name === './band_utils.js') {
        return {
          parseJson: function(value) { return JSON.parse(value) },
          padZero: function(value) { return ('0' + value).slice(-2) }
        }
      }
      throw new Error('Unexpected import: ' + name)
    },
    setTimeout: function(callback, delay) {
      var id = nextTimerId++
      timers[id] = { due: now + delay, callback: callback }
      return id
    },
    clearTimeout: function(id) { delete timers[id] },
    Date: Date,
    Promise: Promise
  }
  vm.runInNewContext(source, context, { filename: 'sync_service.js' })
  return {
    sync: module.exports,
    savedTodos: function() { return JSON.parse(saved.sync_todo) },
    writes: function() { return writes },
    sent: sent,
    advance: function(milliseconds) {
      var target = now + milliseconds
      while (true) {
        var nextId = null
        var nextDue = Infinity
        Object.keys(timers).forEach(function(id) {
          if (timers[id].due <= target && timers[id].due < nextDue) {
            nextId = id
            nextDue = timers[id].due
          }
        })
        if (nextId === null) break
        now = nextDue
        var callback = timers[nextId].callback
        delete timers[nextId]
        callback()
      }
      now = target
    }
  }
}

function batch(items, number, total, transferId) {
  return {
    type: 'todo',
    data: items,
    batchNum: number,
    totalBatches: total,
    transferId: transferId
  }
}

function test(name, run) {
  run()
  process.stdout.write('PASS ' + name + '\n')
}

test('missing batch never replaces the complete cache or reports success', function() {
  var harness = createHarness()
  var result = null
  harness.sync.requestSyncFromPhone('todo', function(value) { result = value })
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2, 'transfer-a'))
  harness.advance(10000)

  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'old-1' }, { id: 'old-2' }])
  assert.strictEqual(harness.writes(), 0)
  assert.strictEqual(result.success, false)
  assert.strictEqual(harness.sent.filter(function(message) {
    return message.type === 'sync_result'
  })[0].success, false)
  harness.sync.handleReceivedData(batch([{ id: 'new-2' }], 2, 2, 'transfer-a'))
  harness.advance(10000)
  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'old-1' }, { id: 'old-2' }])
  assert.strictEqual(harness.writes(), 0)
})

test('out-of-order complete batches replace data only after the last batch', function() {
  var harness = createHarness()
  var result = null
  var notifications = 0
  harness.sync.setOnSyncDataReceived(function() { notifications++ })
  harness.sync.requestSyncFromPhone('todo', function(value) { result = value })
  harness.sync.handleReceivedData(batch([{ id: 'new-2' }], 2, 2, 'transfer-b'))
  assert.strictEqual(harness.writes(), 0)
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2, 'transfer-b'))

  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'new-1', status: 'undone' }, { id: 'new-2', status: 'undone' }])
  assert.strictEqual(harness.writes(), 1)
  assert.strictEqual(notifications, 1)
  assert.strictEqual(result.success, true)
  assert.strictEqual(harness.sent.filter(function(message) {
    return message.type === 'sync_result'
  })[0].success, true)
})

test('a new transfer cannot mix its batches with an older transfer', function() {
  var harness = createHarness()
  harness.sync.handleReceivedData(batch([{ id: 'stale' }], 1, 2, 'transfer-a'))
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2, 'transfer-b'))
  harness.sync.handleReceivedData(batch([{ id: 'new-2' }], 2, 2, 'transfer-b'))
  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'new-1', status: 'undone' }, { id: 'new-2', status: 'undone' }])
  assert.strictEqual(harness.writes(), 1)
  var results = harness.sent.filter(function(message) {
    return message.type === 'sync_result'
  })
  assert.strictEqual(results.length, 2)
  assert.strictEqual(results[0].transferId, 'transfer-a')
  assert.strictEqual(results[0].success, false)
  assert.strictEqual(results[1].transferId, 'transfer-b')
  assert.strictEqual(results[1].success, true)
})

test('batches from older phone versions without transfer ids still work', function() {
  var harness = createHarness()
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2))
  harness.sync.handleReceivedData(batch([{ id: 'new-2' }], 2, 2))
  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'new-1', status: 'undone' }, { id: 'new-2', status: 'undone' }])
  assert.strictEqual(harness.writes(), 1)
  assert.strictEqual(harness.sent.filter(function(message) {
    return message.type === 'sync_result'
  }).length, 0)
})

test('invalid batch indexes never count toward a complete transfer', function() {
  var harness = createHarness()
  harness.sync.handleReceivedData(batch([{ id: 'bad' }], 3, 2, 'transfer-c'))
  harness.sync.handleReceivedData(batch([{ id: 'bad' }], 1, 10001, 'transfer-c'))
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2, 'transfer-c'))
  harness.advance(10000)
  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'old-1' }, { id: 'old-2' }])
  assert.strictEqual(harness.writes(), 0)
})

test('storage failure is reported instead of a successful sync', function() {
  var harness = createHarness({ failStorage: true })
  var result = null
  harness.sync.requestSyncFromPhone('todo', function(value) { result = value })
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 1, 'transfer-d'))
  assert.deepStrictEqual(harness.savedTodos(), [{ id: 'old-1' }, { id: 'old-2' }])
  assert.strictEqual(result.success, false)
  assert.strictEqual(harness.sent.filter(function(message) {
    return message.type === 'sync_result'
  })[0].success, false)
})

test('a complete empty snapshot can intentionally clear the old cache', function() {
  var harness = createHarness()
  var result = null
  harness.sync.requestSyncFromPhone('todo', function(value) { result = value })
  harness.sync.handleReceivedData(batch([], 1, 1, 'transfer-empty'))
  assert.deepStrictEqual(harness.savedTodos(), [])
  assert.strictEqual(harness.writes(), 1)
  assert.strictEqual(result.success, true)
})

test('receiving the first batch extends the initial request timeout', function() {
  var harness = createHarness()
  var result = null
  harness.sync.requestSyncFromPhone('todo', function(value) { result = value })
  harness.advance(7000)
  harness.sync.handleReceivedData(batch([{ id: 'new-1' }], 1, 2, 'transfer-e'))
  harness.advance(2000)
  assert.strictEqual(result, null)
  harness.sync.handleReceivedData(batch([{ id: 'new-2' }], 2, 2, 'transfer-e'))
  assert.strictEqual(result.success, true)
})
