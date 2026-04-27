package com.xiaomi.xms.wearable.demo.ui.sample

import android.app.Activity
import android.os.Bundle
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.demo.databinding.ActivityCommonsampleBinding
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener
import com.xiaomi.xms.wearable.service.ServiceApi

class CommonSampleActivity:Activity() {

    companion object{
        const val TAG = "CommonSample"
    }

   private lateinit var binding:ActivityCommonsampleBinding

    private var nodeApi: NodeApi? = null
    private var serviceApi:ServiceApi? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nodeApi = Wearable.getNodeApi(applicationContext)
        serviceApi = Wearable.getServiceApi(applicationContext)
        binding = ActivityCommonsampleBinding.inflate(layoutInflater)
        val view = binding.root
        setContentView(view)
        initView()
        getConnectedDevice()
    }

    val serviceRegisterListener = object :
        OnServiceConnectionListener {
        override fun onServiceConnected() {
            binding.status.text = "service connected"

        }

        override fun onServiceDisconnected() {
            binding.status.text = "service disconnected"
        }

    }

    var curNode: Node? = null
    private fun initView() {
        binding.getConnectedDevice.setOnClickListener {
            getConnectedDevice()
        }


        binding.isAppInstalled.setOnClickListener {
            curNode?.let { node ->
                nodeApi?.isWearAppInstalled(node.id)?.addOnSuccessListener {
                    binding.status.text = "get watch app installed result is $it"
                }?.addOnFailureListener {
                    binding.status.text = "get watch app installed failed exception:${it.message}"
                }
            }
        }


        binding.registerServiceConnectedListener.setOnClickListener {
            serviceApi?.registerServiceConnectionListener(serviceRegisterListener)
        }

        binding.launchApp.setOnClickListener {
            curNode?.let { node ->
                nodeApi?.launchWearApp(node.id,"/home")?.addOnSuccessListener {
                    binding.status.text = "launch app success"
                }?.addOnFailureListener {
                    binding.status.text = "launch app failed ${it.message}"
                }
            }
        }

    }
    private fun getConnectedDevice() {
        nodeApi?.connectedNodes?.addOnSuccessListener {
            if(it.size > 0) curNode = it[0]
            binding.status.text = curNode.toString()
        }?.addOnFailureListener {
            binding.status.text = "get connected nodes failed message = ${it.message}"
        }
    }


}