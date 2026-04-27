package com.xiaomi.xms.wearable.demo.ui.home

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import androidx.lifecycle.ViewModelProvider
import com.xiaomi.xms.wearable.demo.databinding.FragmentHomeBinding
import com.xiaomi.xms.wearable.demo.ui.sample.CommonSampleActivity
import com.xiaomi.xms.wearable.demo.ui.sample.PermissionSampleActivity
import com.xiaomi.xms.wearable.demo.ui.sample.StatusQuerySampleActivity
import com.xiaomi.xms.wearable.demo.ui.sample.StatusSubscribeSampleActivity

class HomeFragment : Fragment() {

    private lateinit var homeViewModel: HomeViewModel
    private var _binding: FragmentHomeBinding? = null

    // This property is only valid between onCreateView and
    // onDestroyView.
    private val binding get() = _binding!!


    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        homeViewModel = ViewModelProvider(this).get(HomeViewModel::class.java)

        _binding = FragmentHomeBinding.inflate(inflater, container, false)

        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        binding.commonDemo.setOnClickListener {
            startActivity(Intent(activity,CommonSampleActivity::class.java))
        }

        binding.statusSubscribeDemo.setOnClickListener {
            startActivity(Intent(activity, StatusSubscribeSampleActivity::class.java))
        }

        binding.statusQueryDemo.setOnClickListener {
            startActivity(Intent(activity,StatusQuerySampleActivity::class.java))
        }

        binding.permissionDemo.setOnClickListener {
            startActivity(Intent(activity,PermissionSampleActivity::class.java))
        }

    }



    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}