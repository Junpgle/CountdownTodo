package com.xiaomi.xms.wearable.demo.ui.sample

import android.app.Activity
import android.os.Bundle
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.demo.databinding.ActivityStatusQueryDemoBinding
import com.xiaomi.xms.wearable.node.DataItem
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi

class StatusQuerySampleActivity:Activity(){

    lateinit var binding: ActivityStatusQueryDemoBinding

    private var nodeApi: NodeApi? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nodeApi = Wearable.getNodeApi(applicationContext)
        binding = ActivityStatusQueryDemoBinding.inflate(layoutInflater)
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
        binding.queryConnectionStatus.setOnClickListener {
            curNode?.let {node ->
                nodeApi?.query(node.id, DataItem.ITEM_CONNECTION)
                    ?.addOnSuccessListener { data ->
                        binding.status.text = "query connection status = ${data.isConnected}"
                    }?.addOnFailureListener {
                        binding.status.text = "query connection failed : message =  ${it.message}"
                    }
            }
        }

        binding.queryChargingStatus.setOnClickListener {
            curNode?.let {node ->
                nodeApi?.query(node.id, DataItem.ITEM_CHARGING)
                    ?.addOnSuccessListener { data ->
                        binding.status.text = "query charging status = ${data.isCharging}"
                    }?.addOnFailureListener {
                        binding.status.text = "query charging failed message = ${it.message}"
                    }
            }
        }

        binding.querySleepStatus.setOnClickListener {
            curNode?.let { node ->
                nodeApi?.query(node.id, DataItem.ITEM_SLEEP)
                    ?.addOnSuccessListener {  data ->
                        binding.status.text = "query sleep status = ${data.isSleeping}"
                    }?.addOnFailureListener {
                        binding.status.text = "query sleep failed message = ${it.message}"
                    }

            }
        }

        binding.queryWearingStatus.setOnClickListener {
            curNode?.let { node ->
                nodeApi?.query(node.id, DataItem.ITEM_WEARING)
                    ?.addOnSuccessListener { data ->
                        binding.status.text = "query wearing status = " + data.isWearing
                    }?.addOnFailureListener {
                        binding.status.text = "query wearing failed message = ${it.message}"
                    }
            }
        }

        binding.queryWarningStatus.setOnClickListener {
            curNode?.let { node ->
                nodeApi?.query(node.id, DataItem.ITEM_BATTERY)
                    ?.addOnSuccessListener { data ->
                        binding.status.text = "query current battery = " + data.battery
                    }?.addOnFailureListener {
                        binding.status.text = "query warning failed message = ${it.message}"
                    }
            }
        }

    }


}