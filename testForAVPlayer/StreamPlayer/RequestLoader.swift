//
//  RequestLoader.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/13.
//  Copyright © 2016年 ymh. All rights reserved.
//  主要为了实现AVAssey

import Foundation
import AVFoundation
import MobileCoreServices

public class RequestLoader: NSObject {
    
    //  publics
    public var task: RequestTask?   //  下载任务
    public var finishLoadingHandler: ((task: RequestTask, errorCode: Int?)->())?    //  下载结果回调
    
    //  privates
    private var pendingRequset = [AVAssetResourceLoadingRequest]()   //  存播放器请求的数据的
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
    
    /**
     播放器关闭了下载请求
     播放器关闭一个旧请求，都会发起一到多个新请求，除非已经播放完毕了
     
     - parameter resourceLoader: 资源管理器
     - parameter loadingRequest: 待关请求
     */
    public func resourceLoader(resourceLoader: AVAssetResourceLoader, didCancelLoadingRequest loadingRequest: AVAssetResourceLoadingRequest) {
        guard let index = pendingRequset.indexOf(loadingRequest) else {return}
        pendingRequset.removeAtIndex(index)
    }
}

extension RequestLoader {
    private func _dealWithLoadingRequest(loadingRequest: AVAssetResourceLoadingRequest) {
        guard let interceptedURL = loadingRequest.request.URL else {return}
        let range = NSMakeRange(Int(loadingRequest.dataRequest?.currentOffset ?? 0),Int.max)
        if let task = task {
            if task.downLoadingOffset > 0 { //  如果该请求正在加载...
                _processPendingRequests()
            }
            //  处理往回拖 & 拖到的位置大于已缓存位置的情况
            let loadLastRequest = range.location < task.offset //   往回拖
            let tmpResourceIsNotEnoughToLoad = task.offset + task.downLoadingOffset + 1024 * 300 < range.location  //  拖到的位置过大，比已缓存的位置还大300
            if loadLastRequest || tmpResourceIsNotEnoughToLoad {
                self.task!.set(URL: interceptedURL, offset: range.location)
            }
        } else {
            task = RequestTask()
            task?.receiveVideoDataHandler = { task in
                self._processPendingRequests()
            }
            task?.receiveVideoFinishHanlder = { task in
                self.finishLoadingHandler?(task: task, errorCode: nil)
            }
            task?.receiveVideoFailHandler = { task, error in
                self.finishLoadingHandler?(task: task, errorCode: error.code)
            }
            task?.set(URL: interceptedURL, offset: 0)
        }
    }
    /**
     处理加载中的请求
     */
    private func _processPendingRequests() {
        var requestsCompleted = [AVAssetResourceLoadingRequest]()
        for loadingRequest in pendingRequset {
            _fillInContentInfomation(loadingRequest.contentInformationRequest)
            //
            let didRespondCompletely = _respondWithData(forRequest: loadingRequest.dataRequest)
            if didRespondCompletely {
                requestsCompleted.append(loadingRequest)
                loadingRequest.finishLoading()
            }
        }
        //  剔除掉已经完成了的请求
        pendingRequset = pendingRequset.filter({ (request) -> Bool in
            return !requestsCompleted.contains(request)
        })
    }
    
    /**
     设置请求信息
     */
    private func _fillInContentInfomation(contentInfomationRequst: AVAssetResourceLoadingContentInformationRequest?) {
        guard let task = task else {return}
        let mimeType = task.mimeType
        let contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType!, nil)?.takeRetainedValue()
        contentInfomationRequst?.byteRangeAccessSupported = true
        contentInfomationRequst?.contentType = CFBridgingRetain(contentType) as? String
        contentInfomationRequst?.contentLength = Int64(task.videoLength)
    }
    
    /**
     响应播放器请求
     
     返回值: 是否能完整的响应该请求 - 给播放器足够的数据
     */
    private func _respondWithData(forRequest dataRequest: AVAssetResourceLoadingDataRequest?) -> Bool{
        guard let dataRequest = dataRequest else {return true}
        guard let task = task else {return false}
        var startOffset = dataRequest.requestedOffset
        if dataRequest.currentOffset != 0 {
            startOffset = dataRequest.currentOffset
        }
        //  如果请求的位置 + 已缓冲了的长度 比新请求的其实位置小 - 隔了一段
        if task.offset + task.downLoadingOffset < Int(startOffset) {
            return false
        } else if Int(startOffset) < task.offset {   //  播放器要的起始位置，在下载器下载的起始位置之前
            return false
        } else {
            //  取出来缓存文件
            var fileData: NSData? = nil
            fileData = NSData(contentsOfFile: StreamAudioConfig.tempPath)
            //  可以拿到的从startOffset之后的长度
            let unreadBytes = task.downLoadingOffset - (Int(startOffset) - task.offset)
            //  应该能拿到的字节数
            let numberOfBytesToRespondWith = min(dataRequest.requestedLength, unreadBytes)
            //  应该从本地拿的数据范围
            let fetchRange = NSMakeRange(Int(startOffset) - task.offset, numberOfBytesToRespondWith)
            //  拿到响应数据
            guard let responseData = fileData?.subdataWithRange(fetchRange) else {return false}
            //  响应请求
            dataRequest.respondWithData(responseData)
            //  请求结束位置
            let endOffset = startOffset + dataRequest.requestedLength
            //  是否获取到完整数据
            let didRespondFully = task.offset + task.downLoadingOffset >= Int(endOffset)
            
            return didRespondFully
        }
    }
}

extension RequestLoader {
    /**
     获取相应协议头的URL
     
     - parameter scheme: 协议头（默认为streaming）
     - parameter url:    待转换URL
     */
    public func getURL(forScheme scheme: String = "streaming", url: NSURL?) -> NSURL? {
        guard let url = url else {return nil}
        let component = NSURLComponents(URL: url, resolvingAgainstBaseURL: false)
        component?.scheme = scheme
        return component?.URL
    }
    
    public func cancel() {
        //  1. 结束task下载任务
        task?.cancel()
        task = nil
        //  2. 停止数据请求
        for request in pendingRequset {
            request.finishLoading()
        }
    }
}