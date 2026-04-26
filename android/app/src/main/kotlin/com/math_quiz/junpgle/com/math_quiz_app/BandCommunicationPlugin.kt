package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.AuthApi
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.message.MessageApi
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener
import com.xiaomi.xms.wearable.service.ServiceApi
import io.flutter.plugin.common.MethodChannel

class BandCommunicationPlugin(private val context: Context, private val channel: MethodChannel) {

    companion object {
        private const val TAG = "BandCommunication"
        private const val MAX_MESSAGE_BYTES = 64 * 1024
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var nodeApi: NodeApi? = null
    private var messageApi: MessageApi? = null
    private var serviceApi: ServiceApi? = null
    private var authApi: AuthApi? = null
    private var currentNode: Node? = null
    private var messageListener: OnMessageReceivedListener? = null
    private var hasDeviceManagerPermission = false

    private fun invokeMethod(method: String, args: Any?) {
        mainHandler.post {
            try {
                channel.invokeMethod(method, args)
            } catch (e: Exception) {
                Log.e(TAG, "invokeMethod $method failed: ${e.message}")
            }
        }
    }

    // 服务连接监听器
    private val serviceConnectionListener = object : OnServiceConnectionListener {
        override fun onServiceConnected() {
            // Log.d(TAG, "小米穿戴服务已连接")
            getConnectedDevice()
        }

        override fun onServiceDisconnected() {
            Log.d(TAG, "小米穿戴服务已断开")
            currentNode = null
            hasDeviceManagerPermission = false
            invokeMethod("onServiceDisconnected", null)
        }
    }

    // 初始化 SDK
    fun init() {
        try {
            nodeApi = Wearable.getNodeApi(context)
            messageApi = Wearable.getMessageApi(context)
            serviceApi = Wearable.getServiceApi(context)
            authApi = Wearable.getAuthApi(context)

            serviceApi?.registerServiceConnectionListener(serviceConnectionListener)
            getConnectedDevice()

            // Log.d(TAG, "小米穿戴 SDK 初始化成功")
        } catch (e: Exception) {
            Log.e(TAG, "小米穿戴 SDK 初始化失败", e)
        }
    }

    // 获取已连接的设备
    fun getConnectedDevice() {
        nodeApi?.connectedNodes?.addOnSuccessListener { nodes ->
            if (nodes.isNotEmpty()) {
                currentNode = nodes[0]
                val deviceInfo = mapOf(
                    "nodeId" to currentNode!!.id,
                    "name" to (currentNode!!.name ?: "小米手环"),
                    "isConnected" to true
                )
                // Log.d(TAG, "获取到已连接设备: $deviceInfo")
                invokeMethod("onDeviceConnected", deviceInfo)
                checkAndRequestPermission()
            } else {
                Log.d(TAG, "没有已连接的设备")
                currentNode = null
                invokeMethod("onDeviceDisconnected", null)
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "获取已连接设备失败", e)
            invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "获取设备失败: ${e.message}"
            ))
        }
    }

    // 检查并申请 DEVICE_MANAGER 权限
    private fun checkAndRequestPermission() {
        val node = currentNode ?: return

        // Log.d(TAG, "checkAndRequestPermission: 检查权限状态...")
        
        authApi?.checkPermission(node.id, Permission.DEVICE_MANAGER)?.addOnSuccessListener { granted ->
            hasDeviceManagerPermission = granted
            Log.d(TAG, "DEVICE_MANAGER 权限状态: $granted")
            
            // 通知 Flutter 当前权限状态
            invokeMethod("onPermissionChecked", mapOf(
                "granted" to granted,
                "permissions" to if (granted) listOf("DEVICE_MANAGER", "NOTIFY") else emptyList<String>()
            ))
            
            if (!granted) {
                Log.d(TAG, "未授权，自动申请...")
                requestPermission()
            } else {
                // 已授权，注册消息监听
                doRegisterListener()
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "检查权限失败: ${e.message}", e)
        }
    }

    // 申请权限
    fun requestPermission() {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "权限申请失败: 没有已连接的设备")
            invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "没有已连接的设备，请先连接手环"
            ))
            return
        }

        if (authApi == null) {
            Log.e(TAG, "权限申请失败: AuthApi 未初始化")
            invokeMethod("onError", mapOf(
                "code" to 1002,
                "message" to "SDK 未初始化，请重新连接"
            ))
            return
        }

        Log.d(TAG, "开始申请权限: DEVICE_MANAGER, NOTIFY")
        Log.d(TAG, "调用 authApi.requestPermission for node: ${node.id}")
        Log.d(TAG, "当前 hasDeviceManagerPermission: $hasDeviceManagerPermission")
        
        // 在主线程调用 requestPermission（需要 UI 上下文）
        mainHandler.post {
            Log.d(TAG, "在主线程执行权限申请...")
            authApi?.requestPermission(node.id, Permission.DEVICE_MANAGER, Permission.NOTIFY)
                ?.addOnSuccessListener { permissions ->
                    hasDeviceManagerPermission = true
                    Log.d(TAG, "权限申请成功: ${permissions.map { it.name }}")
                    invokeMethod("onPermissionGranted", mapOf(
                        "permissions" to permissions.map { it.name }
                    ))
                    doRegisterListener()
                }
                ?.addOnFailureListener { e ->
                    Log.e(TAG, "权限申请失败: ${e.message}", e)
                    val errorMsg = e.message ?: ""
                    
                    // app not installed 错误 - 尝试先启动小程序
                    if (errorMsg.contains("app not installed", ignoreCase = true)) {
                        Log.d(TAG, "小程序未安装或未启动，尝试启动...")
                        invokeMethod("onError", mapOf(
                            "code" to 1009,
                            "message" to "手环小程序未运行，请先在手环上打开小程序后再试"
                        ))
                        return@addOnFailureListener
                    }
                    
                    if (errorMsg.contains("connection", ignoreCase = true) || 
                        errorMsg.contains("timeout", ignoreCase = true) ||
                        errorMsg.contains("Cronet")) {
                        Log.d(TAG, "网络超时，检查当前权限状态...")
                        checkCurrentPermissionAndNotify()
                        return@addOnFailureListener
                    }
                    when {
                        errorMsg.contains("permission", ignoreCase = true) -> {
                            invokeMethod("onError", mapOf(
                                "code" to 1004,
                                "message" to "权限被拒绝，请在小米穿戴App中手动授权DEVICE_MANAGER权限"
                            ))
                        }
                        errorMsg.contains("service", ignoreCase = true) -> {
                            invokeMethod("onError", mapOf(
                                "code" to 1005,
                                "message" to "小米穿戴服务未运行，请确保小米穿戴App在后台运行"
                            ))
                        }
                        else -> {
                            invokeMethod("onError", mapOf(
                                "code" to 1003,
                                "message" to "权限申请失败: $errorMsg"
                            ))
                        }
                    }
                }
            Log.d(TAG, "requestPermission 调用已发出")
        }
    }

    // 发送消息到手环
    fun sendNotificationToBand(title: String, content: String, todoType: String, notificationId: Int) {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "发送手环通知失败: 没有已连接的设备")
            return
        }
        if (!hasDeviceManagerPermission) {
            Log.e(TAG, "发送手环通知失败: 没有 DEVICE_MANAGER 权限")
            return
        }
        val payload = org.json.JSONObject().apply {
            put("type", "special_todo_notification")
            put("data", org.json.JSONObject().apply {
                put("title", title)
                put("content", content)
                put("todoType", todoType)
                put("notificationId", notificationId)
                put("timestamp", System.currentTimeMillis())
            })
        }.toString()
        Log.d(TAG, "发送手环通知: $payload")
        messageApi?.sendMessage(node.id, payload.toByteArray())?.addOnSuccessListener {
            Log.d(TAG, "手环通知发送成功: $title")
            nodeApi?.launchWearApp(node.id, "/home")?.addOnSuccessListener {
                Log.d(TAG, "已自动打开手环应用（消息处理后将跳转提醒页面）")
            }?.addOnFailureListener { e ->
                Log.e(TAG, "打开手环应用失败", e)
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "手环通知发送失败", e)
        }
    }

    fun sendMessage(data: String) {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "发送消息失败: 没有已连接的设备")
            invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "没有已连接的设备"
            ))
            return
        }

        if (!hasDeviceManagerPermission) {
            Log.e(TAG, "发送消息失败: 没有 DEVICE_MANAGER 权限")
            invokeMethod("onError", mapOf(
                "code" to 1001,
                "message" to "缺少 DEVICE_MANAGER 权限"
            ))
            return
        }

        val dataBytes = data.toByteArray()
        if (dataBytes.size > MAX_MESSAGE_BYTES) {
            Log.e(TAG, "发送消息失败: 消息过大 ${dataBytes.size} bytes")
            invokeMethod("onError", mapOf(
                "code" to 1010,
                "message" to "发送失败: 消息过大，请减少同步数据"
            ))
            return
        }

        messageApi?.sendMessage(node.id, dataBytes)?.addOnSuccessListener {
            Log.d(TAG, "消息发送成功: ${dataBytes.size} bytes")
            invokeMethod("onMessageSent", mapOf("success" to true))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "消息发送失败", e)
            invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "发送失败: ${e.message}"
            ))
        }
    }

    // 注册消息监听器
    fun registerMessageListener() {
        val node = currentNode
        if (node == null) {
            Log.d(TAG, "当前没有已连接设备，尝试获取...")
            nodeApi?.connectedNodes?.addOnSuccessListener { nodes ->
                if (nodes.isNotEmpty()) {
                    currentNode = nodes[0]
                    Log.d(TAG, "获取到设备: ${currentNode!!.name}")
                    doRegisterListener()
                } else {
                    Log.e(TAG, "注册监听器失败: 没有已连接的设备")
                    invokeMethod("onError", mapOf(
                        "code" to 1006,
                        "message" to "没有已连接的设备"
                    ))
                }
            }?.addOnFailureListener { e ->
                Log.e(TAG, "获取设备失败", e)
                invokeMethod("onError", mapOf(
                    "code" to 1000,
                    "message" to "获取设备失败: ${e.message}"
                ))
            }
        } else {
            doRegisterListener()
        }
    }

    // 实际执行注册监听器
    private fun doRegisterListener() {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "doRegisterListener: node is null")
            invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "设备未连接"
            ))
            return
        }

        if (messageApi == null) {
            Log.e(TAG, "doRegisterListener: messageApi is null")
            invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "SDK 未初始化"
            ))
            return
        }

        if (!hasDeviceManagerPermission) {
            Log.e(TAG, "doRegisterListener: 没有 DEVICE_MANAGER 权限")
            invokeMethod("onError", mapOf(
                "code" to 1001,
                "message" to "缺少 DEVICE_MANAGER 权限，请先申请权限"
            ))
            return
        }

        // Log.d(TAG, "doRegisterListener: nodeId=${node.id}, nodeName=${node.name}")

        // 先移除旧的监听器
        unregisterMessageListener()

        messageListener = OnMessageReceivedListener { nodeId, message ->
            if (message.size > MAX_MESSAGE_BYTES) {
                Log.e(TAG, "丢弃过大的手环消息: ${message.size} bytes")
                invokeMethod("onError", mapOf(
                    "code" to 1011,
                    "message" to "收到的手环消息过大，已丢弃"
                ))
                return@OnMessageReceivedListener
            }
            val messageStr = String(message)
            Log.d(TAG, "收到手环消息: $messageStr")
            invokeMethod("onMessageReceived", mapOf("data" to messageStr))
        }

        // Log.d(TAG, "调用 addListener...")
        messageApi?.addListener(node.id, messageListener!!)
            ?.addOnSuccessListener {
                // Log.d(TAG, "消息监听器注册成功")
                invokeMethod("onListenerRegistered", mapOf("success" to true))
            }
            ?.addOnFailureListener { e ->
                Log.e(TAG, "消息监听器注册失败: ${e.message}", e)
                invokeMethod("onError", mapOf(
                    "code" to 1000,
                    "message" to "注册监听器失败: ${e.message}"
                ))
            }
    }

    // 取消消息监听器
    fun unregisterMessageListener() {
        val node = currentNode ?: return
        val listener = messageListener ?: return

        messageApi?.removeListener(node.id)?.addOnSuccessListener {
            // Log.d(TAG, "消息监听器取消成功")
        }?.addOnFailureListener { e ->
            // Log.e(TAG, "消息监听器取消失败", e)
        }
        messageListener = null
    }

    // 检查手环端应用是否安装
    fun isAppInstalled() {
        val node = currentNode
        if (node == null) {
            invokeMethod("onAppInstallResult", mapOf("installed" to false))
            return
        }

        nodeApi?.isWearAppInstalled(node.id)?.addOnSuccessListener { installed ->
            Log.d(TAG, "手环端应用安装状态: $installed")
            invokeMethod("onAppInstallResult", mapOf("installed" to installed))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "检查应用安装状态失败", e)
            invokeMethod("onAppInstallResult", mapOf("installed" to false))
        }
    }

    // 启动手环端应用
    fun launchApp() {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "启动应用失败: 没有已连接的设备")
            invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "没有已连接的设备"
            ))
            return
        }

        nodeApi?.launchWearApp(node.id, "/home")?.addOnSuccessListener {
            Log.d(TAG, "手环端应用启动成功")
            invokeMethod("onAppLaunched", mapOf("success" to true))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "手环端应用启动失败", e)
            invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "启动应用失败: ${e.message}"
            ))
        }
    }

    // 获取连接状态
    fun getConnectionStatus(): Map<String, Any> {
        return mapOf(
            "isConnected" to (currentNode != null),
            "nodeId" to (currentNode?.id ?: ""),
            "name" to (currentNode?.name ?: ""),
            "hasPermission" to hasDeviceManagerPermission
        )
    }

    // 检查当前权限状态并通知 Flutter
    private fun checkCurrentPermissionAndNotify() {
        val node = currentNode ?: return
        authApi?.checkPermission(node.id, Permission.DEVICE_MANAGER)?.addOnSuccessListener { granted ->
            hasDeviceManagerPermission = granted
            Log.d(TAG, "当前权限状态: $granted")
            if (granted) {
                invokeMethod("onPermissionGranted", mapOf(
                    "permissions" to listOf("DEVICE_MANAGER", "NOTIFY")
                ))
                doRegisterListener()
            } else {
                invokeMethod("onError", mapOf(
                    "code" to 1007,
                    "message" to "网络超时，如已手动授权请忽略，否则请到小米运动健康App中授权"
                ))
            }
        }?.addOnFailureListener {
            invokeMethod("onError", mapOf(
                "code" to 1008,
                "message" to "网络超时，无法检查权限状态"
            ))
        }
    }

    // 释放资源
    fun dispose() {
        unregisterMessageListener()
        serviceApi?.unregisterServiceConnectionListener(serviceConnectionListener)
        nodeApi = null
        messageApi = null
        serviceApi = null
        authApi = null
        currentNode = null
        hasDeviceManagerPermission = false
    }
}
