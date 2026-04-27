package com.xiaomi.xms.wearable.demo.ui.sample

import android.app.Activity
import android.os.Bundle
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.auth.AuthApi
import com.xiaomi.xms.wearable.auth.Permission
import com.xiaomi.xms.wearable.demo.databinding.ActivityPermissionDemoBinding
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener

class PermissionSampleActivity: Activity() {

    lateinit var binding: ActivityPermissionDemoBinding
    private var nodeApi: NodeApi? = null
    private var authApi: AuthApi? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nodeApi = Wearable.getNodeApi(applicationContext)
        authApi = Wearable.getAuthApi(applicationContext)
        binding = ActivityPermissionDemoBinding.inflate(layoutInflater)
        setContentView(binding.root)
        initView()
        getConnectedDevice()
    }

    private fun getConnectedDevice() {
        nodeApi?.connectedNodes?.addOnSuccessListener {
            if(it.size > 0) curNode = it[0]
            binding.status.text = curNode.toString()
        }?.addOnFailureListener {
            binding.status.text = "get connected devices failed ${it.message}"
        }
    }

    var curNode: Node? = null
    private fun initView() {
        binding.checkPermissionGranted.setOnClickListener {
            curNode?.let { node ->
                val permissions = arrayOf<Permission>(Permission.DEVICE_MANAGER,Permission.NOTIFY)
                authApi?.checkPermissions(node.id,permissions)?.addOnSuccessListener {
                    val isPermissionGranted = mutableListOf<String>()
                    for((index,permission) in permissions.withIndex()){
                        isPermissionGranted.add("${permission.name} grant status is ${it[index]}")
                    }
                    binding.status.text = "check permissions result is $isPermissionGranted"
                }?.addOnFailureListener {
                    binding.status.text = "check permissions failed:${it.message}"
                }
            }
        }

        binding.requestPermissions.setOnClickListener {
            curNode?.let { node ->
                authApi?.requestPermission(node.id, Permission.DEVICE_MANAGER, Permission.NOTIFY)
                    ?.addOnSuccessListener { permissions ->
                        val permissionGrantedList = mutableListOf<String>()
                        for(permission in permissions){
                            permissionGrantedList.add(permission.name)
                        }
                        binding.status.text = "granted permission is $permissionGrantedList"
                    }?.addOnFailureListener {
                        binding.status.text = "request permission failed:${it.message}"
                    }
            }
        }
    }


}