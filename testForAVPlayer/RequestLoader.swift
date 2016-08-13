//
//  RequestLoader.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/13.
//  Copyright © 2016年 ymh. All rights reserved.
//  主要为了实现AVAssey

import Foundation
import AVFoundation

public class RequestLoader: NSURLConnection {    //  为啥要继承自NSURLConnection呢？
    
    //  publics
    public var task: RequestTask?   //  下载任务
    public var FinishLoadingHandler: ((task: RequestTask, errorCode: Int?)->())?    //  下载结果回调
    
    //  privates
    private var pendingRequset = [AVAssetResourceLoadingRequest]()   //  存播放器请求的数据的
    private var videoPath: NSString?                //  缓存路径
    
    override init() {
        super.init()
        
        let document = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).last! as NSString
        videoPath = document.stringByAppendingPathComponent("temp.mp4")
        
        print("缓存路径为 - \(videoPath)")
    }
}

extension RequestLoader: AVAssetResourceLoaderDelegate {
    /**
     播放器问：是否应该等这requestResource加载完再说？
     这里会出现很多个loadingRequest请求， 需要为每一次请求作出处理
     
     - parameter resourceLoader: 资源管理器
     - parameter loadingRequest: 每一小块数据的请求
     
     - returns: <#return value description#>
     */
    public func resourceLoader(resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        //  添加请求到队列
        pendingRequset.append(loadingRequest)
        //  处理请求
        _dealWithLoadingRequest(loadingRequest)
        print("----\(loadingRequest)")
        return true
    }
    
    
}

extension RequestLoader {
    private func _dealWithLoadingRequest(loadingRequest: AVAssetResourceLoadingRequest) {
        
    }
}