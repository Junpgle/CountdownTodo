package com.xiaomi.xms.wearable.demo.ui.notifications

import android.content.Context
import android.os.Bundle
import android.text.TextUtils
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.xiaomi.xms.wearable.Wearable
import com.xiaomi.xms.wearable.demo.databinding.FragmentNotificationsBinding
import com.xiaomi.xms.wearable.exception.ExceptionUtil
import com.xiaomi.xms.wearable.message.MessageApi
import com.xiaomi.xms.wearable.node.Node
import com.xiaomi.xms.wearable.node.NodeApi
import com.xiaomi.xms.wearable.notify.NotifyApi

class NotificationsFragment : Fragment() {

    private lateinit var notificationsViewModel: NotificationsViewModel
    private var _binding: FragmentNotificationsBinding? = null

    // This property is only valid between onCreateView and
    // onDestroyView.
    private val binding get() = _binding!!
    private var nodeApi: NodeApi? = null
    private var notifyApi:NotifyApi? = null

    override fun onAttach(context: Context) {
        super.onAttach(context)
        nodeApi = Wearable.getNodeApi(context.applicationContext)
        notifyApi = Wearable.getNotifyApi(context.applicationContext)
    }

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        notificationsViewModel =
            ViewModelProvider(this).get(NotificationsViewModel::class.java)

        _binding = FragmentNotificationsBinding.inflate(inflater, container, false)

        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        getConnectedNodes()
        binding.sendNotification.setOnClickListener {
            val title = binding.etTitle.text.toString()
            val message = binding.etMessage.text.toString()
            if(TextUtils.isEmpty(title) || TextUtils.isEmpty(message)){
                binding.status.text = "please insert title and message"
                return@setOnClickListener
            }
            curNode?.let { node ->
                notifyApi?.sendNotify(node.id,title,message)?.addOnSuccessListener {
                    binding.status.text = "sendNotify success"
                }?.addOnFailureListener {
                    binding.status.text = "sendNotify failed:${it.message}"
                }
            }

        }
    }
    var curNode: Node? = null
    private fun getConnectedNodes() {
        nodeApi?.connectedNodes?.addOnSuccessListener {
            if (it.size > 0) {
                curNode = it[0]
                binding.status.text = "current node is ${curNode.toString()}"
            }
        }?.addOnFailureListener {
            binding.status.text = "get connected devices failed ${it.message}"
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}