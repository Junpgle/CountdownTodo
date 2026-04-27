package com.xiaomi.xms.wearable.demo.ui.home;

import android.content.Context;

import androidx.annotation.NonNull;

import com.xiaomi.xms.wearable.Status;
import com.xiaomi.xms.wearable.Wearable;
import com.xiaomi.xms.wearable.auth.AuthApi;
import com.xiaomi.xms.wearable.auth.Permission;
import com.xiaomi.xms.wearable.message.MessageApi;
import com.xiaomi.xms.wearable.message.OnMessageReceivedListener;
import com.xiaomi.xms.wearable.node.DataItem;
import com.xiaomi.xms.wearable.node.DataQueryResult;
import com.xiaomi.xms.wearable.node.DataSubscribeResult;
import com.xiaomi.xms.wearable.node.Node;
import com.xiaomi.xms.wearable.node.NodeApi;
import com.xiaomi.xms.wearable.node.OnDataChangedListener;
import com.xiaomi.xms.wearable.notify.NotifyApi;
import com.xiaomi.xms.wearable.service.OnServiceConnectionListener;
import com.xiaomi.xms.wearable.service.ServiceApi;
import com.xiaomi.xms.wearable.tasks.OnFailureListener;
import com.xiaomi.xms.wearable.tasks.OnSuccessListener;

import org.jetbrains.annotations.NotNull;

import java.util.List;

public class Example {

    public void example(Context context){
        NodeApi api = Wearable.getNodeApi(context);
        api.getConnectedNodes().addOnSuccessListener(new OnSuccessListener<List<Node>>() {
            @Override
            public void onSuccess(List<Node> var1) {

            }
        }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull @NotNull Exception var1) {

            }
        });


        AuthApi authApi = Wearable.getAuthApi(context);
        String did = "";
        authApi.checkPermission(did,Permission.DEVICE_MANAGER)
                .addOnSuccessListener(new OnSuccessListener<Boolean>() {
                    @Override
                    public void onSuccess(Boolean result) {

                    }
                }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull Exception exception ) {

            }
        });

        Permission[] permissions = new Permission[]{Permission.DEVICE_MANAGER};
        authApi.checkPermissions(did,permissions)
                .addOnSuccessListener(new OnSuccessListener<boolean[]>() {
                    @Override
                    public void onSuccess(boolean[] var1) {

                    }
                }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull @NotNull Exception var1) {

            }
        });

        authApi.requestPermission(did,Permission.DEVICE_MANAGER)
                .addOnSuccessListener(new OnSuccessListener<Permission[]>() {
                    @Override
                    public void onSuccess(Permission[] permissions) {
                       //请求授权成功，返回授权成功的权限
                    }
                }).addOnFailureListener(new OnFailureListener() {
                @Override
                    public void onFailure(@NonNull Exception var1) {

                    }
                });
       api.query("nodeId", DataItem.ITEM_CONNECTION)
            .addOnSuccessListener(new OnSuccessListener<DataQueryResult>() {
                @Override
                public void onSuccess(DataQueryResult result) {
                   //查询设备连接状态
                   boolean connectionStatus = result.isConnected;
                }
            }).addOnFailureListener(new OnFailureListener() {
                @Override
                   public void onFailure(@NonNull Exception e) {

                   }
               });

       OnDataChangedListener onDataChangedListener = new OnDataChangedListener() {
           @Override
           public void onDataChanged(@NonNull String nodeId, @NotNull DataItem dataItem, @NotNull DataSubscribeResult data) {
               //收到订阅状态变更通知
                if(dataItem.getType() == DataItem.ITEM_CONNECTION.getType()){
                    int connectionStatus = data.getConnectedStatus();
                    if(connectionStatus == DataSubscribeResult.RESULT_CONNECTION_CONNECTED){
                        //设备连接状态变更为已连接状态
                    }
                }
           }
       };

       api.subscribe("nodeId", DataItem.ITEM_CONNECTION, onDataChangedListener)
                .addOnSuccessListener(new OnSuccessListener<Void>() {
                    @Override
                    public void onSuccess(Void var1) {

                    }
                }).addOnFailureListener(new OnFailureListener() {
           @Override
           public void onFailure(@NonNull @NotNull Exception var1) {

           }
       });
       api.unsubscribe("nodeId",DataItem.ITEM_CONNECTION )
                .addOnSuccessListener(new OnSuccessListener<Void>() {
                    @Override
                    public void onSuccess(Void var1) {

                    }
                }).addOnFailureListener(new OnFailureListener() {
           @Override
           public void onFailure(@NonNull @NotNull Exception var1) {

           }
       });

       api.isWearAppInstalled("nodeId")
           .addOnSuccessListener(new OnSuccessListener<Boolean>() {
               @Override
               public void onSuccess(Boolean result) {

               }
           }).addOnFailureListener(new OnFailureListener() {
               @Override
               public void onFailure(@NonNull  Exception e) {

               }
           });

       api.launchWearApp("nodeId","/home")
           .addOnSuccessListener(new OnSuccessListener<Void>() {
               @Override
               public void onSuccess(Void var1) {
                    //打开穿戴设备端应用成功
               }
           }).addOnFailureListener(new OnFailureListener() {
               @Override
               public void onFailure(@NonNull @NotNull Exception var1) {
                   //打开穿戴设备端应用失败
               }
           });

       byte[] messageBytes = new byte[1024];
        MessageApi messageApi = Wearable.getMessageApi(context);
        messageApi.sendMessage("nodeId",messageBytes)
            .addOnSuccessListener(new OnSuccessListener<Void>() {
                @Override
                public void onSuccess(Void var1) {

                }
            })
            .addOnFailureListener(new OnFailureListener() {
                @Override
                public void onFailure(@NonNull Exception e) {
                   //发送数据失败
                }
            });

        OnMessageReceivedListener onMessageReceivedListener = new OnMessageReceivedListener() {
            @Override
            public void onMessageReceived(@NotNull String nodeId,  @NotNull byte[] message) {
                //收到手表端应用发来的消息
            }
        };

        messageApi.addListener("nodeId", onMessageReceivedListener).addOnSuccessListener(new OnSuccessListener<Void>() {
            @Override
            public void onSuccess(Void var1) {

            }
        }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull @NotNull Exception var1) {

            }
        });

        messageApi.removeListener("nodeId")
                .addOnSuccessListener(new OnSuccessListener<Void>() {
                    @Override
                    public void onSuccess(Void var1) {

                    }
                }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull @NotNull Exception var1) {

            }
        });

        NotifyApi notifyApi = Wearable.getNotifyApi(context);
        notifyApi.sendNotify("nodeId","title","message")
                .addOnSuccessListener(new OnSuccessListener<Status>() {
                    @Override
                    public void onSuccess(Status status) {
                        if(status.isSuccess()){
                            //发送通知成功
                        }
                    }
                }).addOnFailureListener(new OnFailureListener() {
            @Override
            public void onFailure(@NonNull @NotNull Exception var1) {
                //发送通知失败
            }
        });

        ServiceApi serviceApi = Wearable.getServiceApi(context);
        OnServiceConnectionListener onServiceConnectionListener = new OnServiceConnectionListener() {
            @Override
            public void onServiceConnected() {
                //服务连接成功
            }

            @Override
            public void onServiceDisconnected() {
                //服务断开
            }
        };
        serviceApi.registerServiceConnectionListener(onServiceConnectionListener);
        serviceApi.unregisterServiceConnectionListener(onServiceConnectionListener);

    }
}
