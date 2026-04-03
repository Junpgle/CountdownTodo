package com.math_quiz.junpgle.com.math_quiz_app

import android.content.Context
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
    }

    private var nodeApi: NodeApi? = null
    private var messageApi: MessageApi? = null
    private var serviceApi: ServiceApi? = null
    private var authApi: AuthApi? = null
    private var currentNode: Node? = null
    private var messageListener: OnMessageReceivedListener? = null
    private var hasDeviceManagerPermission = false

    // 服务连接监听器
    private val serviceConnectionListener = object : OnServiceConnectionListener {
        override fun onServiceConnected() {
            Log.d(TAG, "小米穿戴服务已连接")
            getConnectedDevice()
        }

        override fun onServiceDisconnected() {
            Log.d(TAG, "小米穿戴服务已断开")
            currentNode = null
            hasDeviceManagerPermission = false
            channel.invokeMethod("onServiceDisconnected", null)
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

            Log.d(TAG, "小米穿戴 SDK 初始化成功")
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
                Log.d(TAG, "获取到已连接设备: $deviceInfo")
                channel.invokeMethod("onDeviceConnected", deviceInfo)

                // 连接成功后自动检查并申请权限
                checkAndRequestPermission()
            } else {
                Log.d(TAG, "没有已连接的设备")
                currentNode = null
                channel.invokeMethod("onDeviceDisconnected", null)
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "获取已连接设备失败", e)
            channel.invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "获取设备失败: ${e.message}"
            ))
        }
    }

    // 检查并申请 DEVICE_MANAGER 权限
    private fun checkAndRequestPermission() {
        val node = currentNode ?: return

        authApi?.checkPermission(node.id, Permission.DEVICE_MANAGER)?.addOnSuccessListener { granted ->
            hasDeviceManagerPermission = granted
            Log.d(TAG, "DEVICE_MANAGER 权限状态: $granted")
            if (!granted) {
                Log.d(TAG, "未授权，自动申请...")
                requestPermission()
            }
        }?.addOnFailureListener { e ->
            Log.e(TAG, "检查权限失败", e)
        }
    }

    // 申请权限
    fun requestPermission() {
        val node = currentNode ?: return

        authApi?.requestPermission(node.id, Permission.DEVICE_MANAGER, Permission.NOTIFY)
            ?.addOnSuccessListener { permissions ->
                hasDeviceManagerPermission = true
                Log.d(TAG, "权限申请成功: ${permissions.map { it.name }}")
                channel.invokeMethod("onPermissionGranted", mapOf(
                    "permissions" to permissions.map { it.name }
                ))
            }
            ?.addOnFailureListener { e ->
                Log.e(TAG, "权限申请失败", e)
                channel.invokeMethod("onError", mapOf(
                    "code" to 1000,
                    "message" to "权限申请失败: ${e.message}"
                ))
            }
    }

    // 发送消息到手环
    fun sendMessage(data: String) {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "发送消息失败: 没有已连接的设备")
            channel.invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "没有已连接的设备"
            ))
            return
        }

        if (!hasDeviceManagerPermission) {
            Log.e(TAG, "发送消息失败: 没有 DEVICE_MANAGER 权限")
            channel.invokeMethod("onError", mapOf(
                "code" to 1001,
                "message" to "缺少 DEVICE_MANAGER 权限"
            ))
            return
        }

        messageApi?.sendMessage(node.id, data.toByteArray())?.addOnSuccessListener {
            Log.d(TAG, "消息发送成功: $data")
            channel.invokeMethod("onMessageSent", mapOf("success" to true))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "消息发送失败", e)
            channel.invokeMethod("onError", mapOf(
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
                    channel.invokeMethod("onError", mapOf(
                        "code" to 1006,
                        "message" to "没有已连接的设备"
                    ))
                }
            }?.addOnFailureListener { e ->
                Log.e(TAG, "获取设备失败", e)
                channel.invokeMethod("onError", mapOf(
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
            channel.invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "设备未连接"
            ))
            return
        }

        if (messageApi == null) {
            Log.e(TAG, "doRegisterListener: messageApi is null")
            channel.invokeMethod("onError", mapOf(
                "code" to 1000,
                "message" to "SDK 未初始化"
            ))
            return
        }

        if (!hasDeviceManagerPermission) {
            Log.e(TAG, "doRegisterListener: 没有 DEVICE_MANAGER 权限")
            channel.invokeMethod("onError", mapOf(
                "code" to 1001,
                "message" to "缺少 DEVICE_MANAGER 权限，请先申请权限"
            ))
            return
        }

        Log.d(TAG, "doRegisterListener: nodeId=${node.id}, nodeName=${node.name}")

        // 先移除旧的监听器
        unregisterMessageListener()

        messageListener = OnMessageReceivedListener { nodeId, message ->
            val messageStr = String(message)
            Log.d(TAG, "收到手环消息: $messageStr")
            channel.invokeMethod("onMessageReceived", mapOf("data" to messageStr))
        }

        Log.d(TAG, "调用 addListener...")
        messageApi?.addListener(node.id, messageListener!!)
            ?.addOnSuccessListener {
                Log.d(TAG, "消息监听器注册成功")
                channel.invokeMethod("onListenerRegistered", mapOf("success" to true))
            }
            ?.addOnFailureListener { e ->
                Log.e(TAG, "消息监听器注册失败: ${e.message}", e)
                channel.invokeMethod("onError", mapOf(
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
            Log.d(TAG, "消息监听器取消成功")
        }?.addOnFailureListener { e ->
            Log.e(TAG, "消息监听器取消失败", e)
        }
        messageListener = null
    }

    // 检查手环端应用是否安装
    fun isAppInstalled() {
        val node = currentNode
        if (node == null) {
            channel.invokeMethod("onAppInstallResult", mapOf("installed" to false))
            return
        }

        nodeApi?.isWearAppInstalled(node.id)?.addOnSuccessListener { installed ->
            Log.d(TAG, "手环端应用安装状态: $installed")
            channel.invokeMethod("onAppInstallResult", mapOf("installed" to installed))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "检查应用安装状态失败", e)
            channel.invokeMethod("onAppInstallResult", mapOf("installed" to false))
        }
    }

    // 启动手环端应用
    fun launchApp() {
        val node = currentNode
        if (node == null) {
            Log.e(TAG, "启动应用失败: 没有已连接的设备")
            channel.invokeMethod("onError", mapOf(
                "code" to 1006,
                "message" to "没有已连接的设备"
            ))
            return
        }

        nodeApi?.launchWearApp(node.id, "/home")?.addOnSuccessListener {
            Log.d(TAG, "手环端应用启动成功")
            channel.invokeMethod("onAppLaunched", mapOf("success" to true))
        }?.addOnFailureListener { e ->
            Log.e(TAG, "手环端应用启动失败", e)
            channel.invokeMethod("onError", mapOf(
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

