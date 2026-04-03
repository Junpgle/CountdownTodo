import storage from '@system.storage'
import interconnect from '@system.interconnect'

const SYNC_KEY_PREFIX = 'sync_'
const LAST_SYNC_TIME_KEY = 'last_sync_time'

export class SyncService {
  static connect = null
  static isConnected = false
  static receivedData = {} // 存储从手机接收的数据

  // 初始化连接
  static init() {
    this.connect = interconnect.instance()
    
    // 注册连接打开回调
    this.connect.onopen = (data) => {
      console.log('连接已建立，是否重连:', data.isReconnected)
      this.isConnected = true
    }
    
    // 注册连接关闭回调
    this.connect.onclose = (data) => {
      console.log('连接已关闭，原因:', data.data, '代码:', data.code)
      this.isConnected = false
    }
    
    // 注册连接错误回调
    this.connect.onerror = (data) => {
      console.error('连接错误:', data.data, '代码:', data.code)
      this.isConnected = false
    }
    
    // 注册接收数据回调
    this.connect.onmessage = (data) => {
      console.log('收到手机数据:', data.data)
      this.handleReceivedData(data.data)
    }
  }
  
  // 处理从手机接收的数据
  static handleReceivedData(data) {
    try {
      const parsedData = JSON.parse(data)
      if (parsedData.type && parsedData.data) {
        this.receivedData[parsedData.type] = {
          data: parsedData.data,
          timestamp: parsedData.timestamp || Date.now(),
          direction: 'phone_to_watch'
        }
        // 合并到本地数据
        this.mergePhoneData(parsedData.type, parsedData.data)
      }
    } catch (error) {
      console.error('处理接收数据失败:', error)
    }
  }
  
  // 检查连接状态
  static checkConnection() {
    return new Promise((resolve, reject) => {
      if (!this.connect) {
        this.init()
      }
      
      this.connect.getReadyState({
        success: (data) => {
          this.isConnected = data.status === 1
          resolve(this.isConnected)
        },
        fail: (data, code) => {
          console.error('获取连接状态失败:', data, code)
          this.isConnected = false
          resolve(false)
        }
      })
    })
  }
  
  // 诊断连接情况
  static diagnosis(timeout = 10000) {
    return new Promise((resolve, reject) => {
      this.connect.diagnosis({
        timeout: timeout,
        success: (data) => {
          resolve(data.status === 0)
        },
        fail: (data, code) => {
          console.error('连接诊断失败:', data, code)
          resolve(false)
        }
      })
    })
  }
  
  // 与手机App同步数据
  static async syncData(type, data) {
    try {
      // 检查连接状态
      const connected = await this.checkConnection()
      if (!connected) {
        return { success: false, message: '未连接到手机App' }
      }
      
      const lastSyncTime = await this.getLastSyncTime(type)
      const dataToSync = data.filter(item => {
        return !lastSyncTime || (item.updatedAt && item.updatedAt > lastSyncTime)
      })
      
      if (dataToSync.length === 0) {
        // 检查是否有从手机接收的数据
        if (this.receivedData[type]) {
          await this.mergePhoneData(type, this.receivedData[type].data)
          delete this.receivedData[type]
          return { success: true, message: '已同步手机数据' }
        }
        return { success: true, message: '没有新数据需要同步' }
      }
      
      // 发送数据到手机App
      const sendResult = await this.sendDataToPhone(type, dataToSync)
      if (!sendResult) {
        return { success: false, message: '发送数据到手机失败' }
      }
      
      // 检查是否有从手机接收的数据
      if (this.receivedData[type]) {
        await this.mergePhoneData(type, this.receivedData[type].data)
        delete this.receivedData[type]
      }
      
      await this.setLastSyncTime(type, Date.now())
      return { success: true, message: `同步了${dataToSync.length}条数据` }
    } catch (error) {
      return { success: false, message: error.message || '同步异常' }
    }
  }
  
  // 发送数据到手机App
  static async sendDataToPhone(type, data) {
    return new Promise((resolve, reject) => {
      this.connect.send({
        data: {
          type: type,
          data: data,
          timestamp: Date.now()
        },
        success: () => {
          console.log(`${type}数据发送成功`)
          resolve(true)
        },
        fail: (data, code) => {
          console.error(`${type}数据发送失败:`, data, code)
          resolve(false)
        }
      })
    })
  }
  
  // 合并手机数据到本地
  static async mergePhoneData(type, phoneData) {
    const localData = await this.getLocalData(type)
    
    for (const phoneItem of phoneData) {
      const localIndex = localData.findIndex(item => item.id === phoneItem.id)
      
      if (localIndex === -1) {
        // 本地没有，直接添加
        localData.push(phoneItem)
      } else {
        // 使用LWW策略：比较时间戳，保留较新的版本
        if (phoneItem.updatedAt > localData[localIndex].updatedAt) {
          localData[localIndex] = phoneItem
        }
      }
    }
    
    await this.saveLocalData(type, localData)
  }
  
  static async getLastSyncTime(type) {
    return new Promise((resolve, reject) => {
      storage.get({
        key: `${LAST_SYNC_TIME_KEY}_${type}`,
        success: (data) => {
          resolve(data ? parseInt(data) : 0)
        },
        fail: (error) => {
          resolve(0)
        }
      })
    })
  }
  
  static async setLastSyncTime(type, timestamp) {
    return new Promise((resolve, reject) => {
      storage.set({
        key: `${LAST_SYNC_TIME_KEY}_${type}`,
        value: timestamp.toString(),
        success: () => {
          resolve()
        },
        fail: (error) => {
          reject(error)
        }
      })
    })
  }
  
  static async getLocalData(type) {
    return new Promise((resolve, reject) => {
      storage.get({
        key: `${SYNC_KEY_PREFIX}${type}`,
        success: (data) => {
          resolve(data ? JSON.parse(data) : [])
        },
        fail: (error) => {
          resolve([])
        }
      })
    })
  }
  
  static async saveLocalData(type, data) {
    return new Promise((resolve, reject) => {
      storage.set({
        key: `${SYNC_KEY_PREFIX}${type}`,
        value: JSON.stringify(data),
        success: () => {
          resolve()
        },
        fail: (error) => {
          reject(error)
        }
      })
    })
  }
  
  static async syncAll() {
    const results = {}
    
    const countdownData = await this.getLocalData('countdown')
    results.countdown = await this.syncData('countdown', countdownData)
    
    const todoData = await this.getLocalData('todo')
    results.todo = await this.syncData('todo', todoData)
    
    const courseData = await this.getLocalData('course')
    results.course = await this.syncData('course', courseData)
    
    return results
  }
}

export default SyncService