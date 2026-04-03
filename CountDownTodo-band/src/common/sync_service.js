import storage from '@system.storage'
import interconnect from '@system.interconnect'

const SYNC_KEY_PREFIX = 'sync_'
const LAST_SYNC_TIME_KEY = 'last_sync_time'

function padZero(num) {
  return num < 10 ? '0' + num : '' + num
}

function flattenArray(arr) {
  var result = []
  for (var i = 0; i < arr.length; i++) {
    if (Array.isArray(arr[i])) {
      for (var j = 0; j < arr[i].length; j++) {
        result.push(arr[i][j])
      }
    } else {
      result.push(arr[i])
    }
  }
  return result
}

export class SyncService {
  static connect = null
  static isConnected = false
  static receivedData = {}

  static batchBuffer = {}

  static pendingSyncRequests = {}

  static init() {
    this.connect = interconnect.instance()

    this.connect.onopen = function(data) {
      SyncService.isConnected = true
    }

    this.connect.onclose = function(data) {
      SyncService.isConnected = false
    }

    this.connect.onerror = function(data) {
      SyncService.isConnected = false
    }

    this.connect.onmessage = function(data) {
      SyncService.handleReceivedData(data)
    }
  }

  static destroy() {
    for (var type in this.batchBuffer) {
      var buffer = this.batchBuffer[type]
      if (buffer.timeout) {
        clearTimeout(buffer.timeout)
        buffer.timeout = null
      }
    }
    this.batchBuffer = {}
    for (var type2 in this.pendingSyncRequests) {
      if (this.pendingSyncRequests[type2].timeout) {
        clearTimeout(this.pendingSyncRequests[type2].timeout)
      }
      if (this.pendingSyncRequests[type2].reject) {
        this.pendingSyncRequests[type2].reject(new Error('destroyed'))
      }
    }
    this.pendingSyncRequests = {}
    this.receivedData = {}
    this.connect = null
    this.isConnected = false
  }

  static handleReceivedData(data) {
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

      if (!parsedData || !parsedData.type) {
        return
      }

      if (parsedData.data !== undefined) {
        var batchNum = parsedData.batchNum || 1
        var totalBatches = parsedData.totalBatches || 1
        var batchData = parsedData.data

        if (totalBatches === 1) {
          SyncService.replacePhoneData(parsedData.type, batchData)
          return
        }

        if (!SyncService.batchBuffer[parsedData.type]) {
          SyncService.batchBuffer[parsedData.type] = {
            batches: [],
            totalBatches: totalBatches,
            timeout: null
          }
        }

        var buffer = SyncService.batchBuffer[parsedData.type]
        buffer.batches[batchNum - 1] = batchData

        var receivedCount = 0
        for (var i = 0; i < buffer.batches.length; i++) {
          if (buffer.batches[i] !== undefined) {
            receivedCount++
          }
        }

        if (receivedCount >= buffer.totalBatches) {
          var allData = flattenArray(buffer.batches)
          SyncService.replacePhoneData(parsedData.type, allData)
          delete SyncService.batchBuffer[parsedData.type]
        } else {
          if (buffer.timeout) clearTimeout(buffer.timeout)
          var type = parsedData.type
          buffer.timeout = setTimeout(function() {
            var collectedData = []
            for (var k = 0; k < buffer.batches.length; k++) {
              if (buffer.batches[k] !== undefined) {
                if (Array.isArray(buffer.batches[k])) {
                  for (var m = 0; m < buffer.batches[k].length; m++) {
                    collectedData.push(buffer.batches[k][m])
                  }
                } else {
                  collectedData.push(buffer.batches[k])
                }
              }
            }
            SyncService.replacePhoneData(type, collectedData)
            delete SyncService.batchBuffer[type]
          }, 10000)
        }
      }
    } catch (error) {}
  }

  static async replacePhoneData(type, phoneData) {
    if (!Array.isArray(phoneData)) {
      await SyncService.saveLocalData(type, phoneData)
      return
    }

    var validItems = []
    for (var i = 0; i < phoneData.length; i++) {
      var item = phoneData[i]
      if (!(item.is_deleted === 1 || item.is_deleted === true)) {
        validItems.push(item)
      }
    }

    var adaptedItems = []
    for (var j = 0; j < validItems.length; j++) {
      adaptedItems.push(SyncService.adaptItem(type, validItems[j]))
    }

    await SyncService.saveLocalData(type, adaptedItems)

    if (SyncService.pendingSyncRequests[type]) {
      var req = SyncService.pendingSyncRequests[type]
      if (req.timeout) clearTimeout(req.timeout)
      if (req.resolve) req.resolve({ success: true, message: '已同步手机数据' })
      delete SyncService.pendingSyncRequests[type]
    }
  }

  static checkConnection() {
    return new Promise(function(resolve) {
      if (!SyncService.connect) {
        SyncService.init()
      }

      SyncService.connect.getReadyState({
        success: function(data) {
          SyncService.isConnected = data.status === 1
          resolve(SyncService.isConnected)
        },
        fail: function() {
          SyncService.isConnected = false
          resolve(false)
        }
      })
    })
  }

  static diagnosis(timeout) {
    return new Promise(function(resolve) {
      SyncService.connect.diagnosis({
        timeout: timeout || 10000,
        success: function(data) {
          resolve(data.status === 0)
        },
        fail: function() {
          resolve(false)
        }
      })
    })
  }

  static async syncData(type, data) {
    try {
      var connected = await SyncService.checkConnection()
      if (!connected) {
        return { success: false, message: '未连接到手机App' }
      }

      var lastSyncTime = await SyncService.getLastSyncTime(type)
      var dataToSync = []
      for (var i = 0; i < data.length; i++) {
        var item = data[i]
        if (!lastSyncTime || (item.updatedAt && item.updatedAt > lastSyncTime)) {
          dataToSync.push(item)
        }
      }

      if (dataToSync.length === 0) {
        return { success: true, message: '没有新数据需要同步' }
      }

      var sendResult = await SyncService.sendDataToPhone(type, dataToSync)
      if (!sendResult) {
        return { success: false, message: '发送数据到手机失败' }
      }

      await SyncService.setLastSyncTime(type, Date.now())
      return { success: true, message: '同步了' + dataToSync.length + '条数据' }
    } catch (error) {
      return { success: false, message: '同步异常' }
    }
  }

  static async sendDataToPhone(type, data) {
    return new Promise(function(resolve) {
      SyncService.connect.send({
        data: {
          type: type,
          data: data,
          timestamp: Date.now()
        },
        success: function() {
          resolve(true)
        },
        fail: function() {
          resolve(false)
        }
      })
    })
  }

  static adaptItem(type, item) {
    var adapted = {}
    for (var key in item) {
      if (item.hasOwnProperty(key)) {
        adapted[key] = item[key]
      }
    }

    if (type === 'countdown') {
      if (adapted.target_time && !adapted.targetDate) {
        adapted.targetDate = adapted.target_time
      }
      if (!adapted.title && adapted.name) {
        adapted.title = adapted.name
      }
    } else if (type === 'todo') {
      if (adapted.content && !adapted.title) {
        adapted.title = adapted.content
      }
      if (adapted.is_completed === 1 || adapted.is_completed === true) {
        adapted.status = 'done'
      } else {
        adapted.status = 'undone'
      }
      if (adapted.created_date && !adapted.startDate) {
        adapted.startDate = adapted.created_date
      }
      if (adapted.due_date && !adapted.endDate) {
        adapted.endDate = adapted.due_date
      }
      if (adapted.remark !== undefined && !adapted.description) {
        adapted.description = adapted.remark
      }
    } else if (type === 'course') {
      if (adapted.courseName && !adapted.name) {
        adapted.name = adapted.courseName
      }
      if (adapted.roomName && !adapted.location) {
        adapted.location = adapted.roomName
      }
      if (adapted.teacherName && !adapted.teacher) {
        adapted.teacher = adapted.teacherName
      }
      if (typeof adapted.startTime === 'number') {
        var h = Math.floor(adapted.startTime / 100)
        var m = adapted.startTime % 100
        adapted.startTime = padZero(h) + ':' + padZero(m)
      }
      if (typeof adapted.endTime === 'number') {
        var h2 = Math.floor(adapted.endTime / 100)
        var m2 = adapted.endTime % 100
        adapted.endTime = padZero(h2) + ':' + padZero(m2)
      }
    }

    return adapted
  }

  static async getLastSyncTime(type) {
    return new Promise(function(resolve) {
      storage.get({
        key: LAST_SYNC_TIME_KEY + '_' + type,
        success: function(data) {
          resolve(data ? parseInt(data) : 0)
        },
        fail: function() {
          resolve(0)
        }
      })
    })
  }

  static async setLastSyncTime(type, timestamp) {
    return new Promise(function(resolve, reject) {
      storage.set({
        key: LAST_SYNC_TIME_KEY + '_' + type,
        value: timestamp.toString(),
        success: function() {
          resolve()
        },
        fail: function(error) {
          reject(error)
        }
      })
    })
  }

  static async getLocalData(type) {
    return new Promise(function(resolve) {
      storage.get({
        key: SYNC_KEY_PREFIX + type,
        success: function(data) {
          resolve(data ? JSON.parse(data) : [])
        },
        fail: function() {
          resolve([])
        }
      })
    })
  }

  static async saveLocalData(type, data) {
    return new Promise(function(resolve, reject) {
      storage.set({
        key: SYNC_KEY_PREFIX + type,
        value: JSON.stringify(data),
        success: function() {
          resolve()
        },
        fail: function(error) {
          reject(error)
        }
      })
    })
  }

  static async requestSyncFromPhone(type) {
    var connected = await SyncService.checkConnection()
    if (!connected) {
      return { success: false, message: '未连接到手机App' }
    }

    var self = SyncService
    return new Promise(function(resolve, reject) {
      self.pendingSyncRequests[type] = {
        resolve: resolve,
        reject: reject,
        timeout: null
      }

      self.pendingSyncRequests[type].timeout = setTimeout(function() {
        if (self.pendingSyncRequests[type]) {
          self.pendingSyncRequests[type].resolve({ success: false, message: '手机未响应' })
          delete self.pendingSyncRequests[type]
        }
      }, 8000)

      self.connect.send({
        data: {
          type: type,
          action: 'request_sync',
          timestamp: Date.now()
        },
        success: function() {},
        fail: function(data, code) {
          if (self.pendingSyncRequests[type]) {
            if (self.pendingSyncRequests[type].timeout) {
              clearTimeout(self.pendingSyncRequests[type].timeout)
            }
            self.pendingSyncRequests[type].resolve({ success: false, message: '发送失败' })
            delete self.pendingSyncRequests[type]
          }
        }
      })
    })
  }

  static async syncAll() {
    var results = {}
    results.todo = await SyncService.requestSyncFromPhone('todo')
    results.course = await SyncService.requestSyncFromPhone('course')
    results.countdown = await SyncService.requestSyncFromPhone('countdown')
    return results
  }

  static sendVersionInfo() {
    if (!this.connect) return
    this.connect.send({
      data: {
        type: 'band_info',
        version: '1.0.0',
        version_code: 1,
        timestamp: Date.now()
      },
      success: function() {},
      fail: function() {}
    })
  }
}

export default SyncService
