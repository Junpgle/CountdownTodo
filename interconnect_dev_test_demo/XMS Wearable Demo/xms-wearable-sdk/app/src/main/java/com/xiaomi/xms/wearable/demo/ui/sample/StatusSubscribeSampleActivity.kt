package com.xiaomi.xms.wearable.demo.ui.sample

import android.app.Activity
import android.os.Bundle
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.demo.databinding.ActivityStatusSubscribeDemoBinding
import com.xiaomi.xms.wearable.node.DataItem
import com.xiaomi.xms.wearable.node.DataSubscribeResult
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi

class StatusSubscribeSampleActivity :Activity(){

    private lateinit var binding:ActivityStatusSubscribeDemoBinding
    private var nodeApi: NodeApi? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        nodeApi = Wearable.getNodeApi(applicationContext)
        binding = ActivityStatusSubscribeDemoBinding.inflate(layoutInflater)
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
        binding.registerConnectedChange.setOnClickListener {
            curNode?.let {
                nodeApi?.subscribe(it.id, DataItem.ITEM_CONNECTION
                ) { nodeId, dataItem, data ->
                    if(dataItem.type == DataItem.ITEM_CONNECTION.type){
                        val connectionType = data.connectedStatus
                        if(connectionType == DataSubscribeResult.RESULT_CONNECTION_CONNECTED) {
                            binding.status.text = "curNode $nodeId is connected"
                            if(nodeId != curNode?.id) getConnectedDevice()
                        }else{
                            binding.status.text = "curNode $nodeId is disconnected"
                        }
                    }
                }?.addOnSuccessListener {
                    binding.status.text = "subscribe connection change success"
                }?.addOnFailureListener {
                    binding.status.text = "subscribe connection change failed ${it.message}"
                }
            }
        }

        binding.registerChargingChange.setOnClickListener {
            curNode?.let {
                nodeApi?.subscribe(it.id, DataItem.ITEM_CHARGING){
                        nodeId, dataItem,data ->
                    if(dataItem.type == DataItem.ITEM_CHARGING.type){
                        when(data.chargingStatus){
                            DataSubscribeResult.RESULT_CHARGING_START -> binding.status.text = "charge status changed to start"
                            DataSubscribeResult.RESULT_CHARGING_FINISH -> binding.status.text = "charge status changed to finish"
                            DataSubscribeResult.RESULT_CHARGING_QUIT -> binding.status.text = "charge status changed to quit"
                        }
                    }
                }?.addOnSuccessListener {
                    binding.status.text = "subscribe  charging change success"
                }?.addOnFailureListener {
                    binding.status.text = "subscribe  charging change failed ${it.message}"
                }
            }
        }

        binding.registerSleepChange.setOnClickListener {
            curNode?.let {
                nodeApi?.subscribe(it.id, DataItem.ITEM_SLEEP){
                        nodeId,dataItem,data ->
                    if(dataItem.type == DataItem.ITEM_SLEEP.type){
                        when(data.sleepStatus){
                            DataSubscribeResult.RESULT_SLEEP_IN -> binding.status.text = "sleep status changed to sleep in"
                            DataSubscribeResult.RESULT_SLEEP_OUT -> binding.status.text = "charge status changed to sleep out"
                        }
                    }
                }?.addOnSuccessListener {
                    binding.status.text = "subscribe  sleep change success"
                }?.addOnFailureListener {
                    binding.status.text = "subscribe  sleep change failed ${it.message}"
                }
            }
        }

        binding.registerWearingChange.setOnClickListener {
            curNode?.let {
                nodeApi?.subscribe(it.id, DataItem.ITEM_WEARING){
                        nodeId,dataItem,data ->
                    if(dataItem.type == DataItem.ITEM_WEARING.type){
                        when(data.wearingStatus){
                            DataSubscribeResult.RESULT_WEARING_ON -> binding.status.text = "wearing status changed to wearing on"
                            DataSubscribeResult.RESULT_WEARING_OFF -> binding.status.text = "wearing status changed to wearing out"
                        }
                    }
                }?.addOnSuccessListener {
                    binding.status.text = "subscribe  wearing change success"
                }?.addOnFailureListener {
                    binding.status.text = "subscribe  wearing change failed ${it.message}"
                }
            }
        }



        binding.unRegisterConnectedChange.setOnClickListener {
            curNode?.let {
                nodeApi?.unsubscribe(it.id, DataItem.ITEM_CONNECTION)?.addOnSuccessListener {
                    binding.status.text = "unsubscribe connection change success"
                }?.addOnFailureListener {
                    binding.status.text = "unsubscribe connection change failed ${it.message}"
                }
            }
        }
        binding.unRegisterChargingChange.setOnClickListener {
            curNode?.let {
                nodeApi?.unsubscribe(it.id, DataItem.ITEM_CHARGING)?.addOnSuccessListener {
                    binding.status.text = "unsubscribe charging change success"
                }?.addOnFailureListener {
                    binding.status.text = "unsubscribe charging change failed ${it.message}"
                }
            }
        }

        binding.unRegisterSleepChange.setOnClickListener {
            curNode?.let {
                nodeApi?.unsubscribe(it.id, DataItem.ITEM_SLEEP)?.addOnSuccessListener {
                    binding.status.text = "unsubscribe sleep change success"
                }?.addOnFailureListener {
                    binding.status.text = "unsubscribe sleep change failed ${it.message}"
                }
            }
        }
        binding.unRegisterWearingChange.setOnClickListener {
            curNode?.let {
                nodeApi?.unsubscribe(it.id, DataItem.ITEM_WEARING)?.addOnSuccessListener {
                    binding.status.text = "unsubscribe wearing change success"
                }?.addOnFailureListener {
                    binding.status.text = "unsubscribe wearing change failed ${it.message}"
                }
            }
        }

    }


}