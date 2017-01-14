//
//  RequestTask.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/12.
//  Copyright © 2016年 ymh. All rights reserved.
//  做下载、持久化的

import Foundation

open class RequestTask: NSObject {
    
    open var url: URL?
    open var offset: Int = 0                 //  请求位置（从哪开始）
    open var taskArr = [NSURLConnection]()   //  NSURLConnection的数组
    open var downLoadingOffset: Int = 0   //  已下载数据长度
    open var videoLength: Int = 0         //  视频总长度
    open var isFinishLoad: Bool = false   //  是否下载完成
    open var mimeType: String?            //  传输文件格式
    
    //  代理方法们
    open var recieveVideoInfoHandler: ((_ task: RequestTask, _ videoLength: Int, _ mimeType: String)->())?  //  获取到了信息
    open var receiveVideoDataHandler: ((_ task: RequestTask)->())?  //  获取到了数据
    open var receiveVideoFinishHanlder: ((_ task: RequestTask)->())?    //  获取信息结束
    open var receiveVideoFailHandler: ((_ task: RequestTask, _ error: NSError)->())?
    
    fileprivate var connection: NSURLConnection?    //  下载连接
    fileprivate var fileHandle: FileHandle?       //  文件下载句柄
    fileprivate var once: Bool = false              //  控制失败后是否重新下载
    
    override init() {
        super.init()
        _initialTmpFile()
    }
    
    fileprivate func _initialTmpFile() {
        do { try FileManager.default.createDirectory(atPath: StreamAudioConfig.audioDicPath, withIntermediateDirectories: true, attributes: nil) } catch { print("creat dic false -- error:\(error)") }
        if FileManager.default.fileExists(atPath: StreamAudioConfig.tempPath) {
            try! FileManager.default.removeItem(atPath: StreamAudioConfig.tempPath)
        }
        FileManager.default.createFile(atPath: StreamAudioConfig.tempPath, contents: nil, attributes: nil)
    }
    
    fileprivate func _updateFilePath(_ url: URL) {
        _initialTmpFile()
        print("缓存文件夹路径 -- \(StreamAudioConfig.audioDicPath)")
    }
}

// MARK: - public funcs
extension RequestTask {
    /**
     连接服务器，请求数据（或拼range请求部分数据）（此方法中会将协议头修改为http）
     
     - parameter offset: 请求位置
     */
    public func set(URL url: URL, offset: Int) {
        
        func initialTmpFile() {
            try! FileManager.default.removeItem(atPath: StreamAudioConfig.tempPath)
            FileManager.default.createFile(atPath: StreamAudioConfig.tempPath, contents: nil, attributes: nil)
        }
        _updateFilePath(url)
        self.url = url
        self.offset = offset
        
        //  如果建立第二次请求，则需初始化缓冲文件
        if taskArr.count >= 1 {
            initialTmpFile()
        }
        
        //  初始化已下载文件长度
        downLoadingOffset = 0
        
        //  把stream://xxx的头换成http://的头
        var actualURLComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        actualURLComponents?.scheme = "http"
        guard let URL = actualURLComponents?.url else {return}
        let request = NSMutableURLRequest(url: URL, cachePolicy: NSURLRequest.CachePolicy.reloadIgnoringCacheData, timeoutInterval: 20.0)
        
        //  若非从头下载，且视频长度已知且大于零，则下载offset到videoLength的范围（拼request参数）
        if offset > 0 && videoLength > 0 {
            request.addValue("bytes=\(offset)-\(videoLength - 1)", forHTTPHeaderField: "Range")
        }
        
        connection?.cancel()
        connection = NSURLConnection(request: request as URLRequest, delegate: self, startImmediately: false)
        connection?.setDelegateQueue(OperationQueue.main)
        connection?.start()
    }
}

// MARK: - NSURLConnectionDataDelegate
extension RequestTask: NSURLConnectionDataDelegate {
    public func connection(_ connection: NSURLConnection, didReceive response: URLResponse) {
        isFinishLoad = false
        guard response is HTTPURLResponse else {return}
        //  解析头部数据
        let httpResponse = response as! HTTPURLResponse
        let dic = httpResponse.allHeaderFields
        let content = dic["Content-Range"] as? String
        let array = content?.components(separatedBy: "/")
        let length = array?.last
        //  拿到真实长度
        var videoLength = 0
        if Int(length ?? "0") == 0 {
            videoLength = Int(httpResponse.expectedContentLength)
        } else {
            videoLength = Int(length!)!
        }
        
        self.videoLength = videoLength
        //TODO: 此处需要修改为真实数据格式 - 从字典中取
        self.mimeType = "video/mp4"
        //  回调
        recieveVideoInfoHandler?(self, videoLength, mimeType!)
        //  连接加入到任务数组中
        taskArr.append(connection)
        //  初始化文件传输句柄
        fileHandle = FileHandle.init(forWritingAtPath: StreamAudioConfig.tempPath)
    }
    
    public func connection(_ connection: NSURLConnection, didReceive data: Data) {
        
        //  寻址到文件末尾
        self.fileHandle?.seekToEndOfFile()
        self.fileHandle?.write(data)
        self.downLoadingOffset += data.count
        self.receiveVideoDataHandler?(self)
        
//        print("线程 - \(NSThread.currentThread())")
        
        //  这里用子线程有问题...
        let queue = DispatchQueue(label: "com.azen.taskConnect", attributes: [])
        queue.async {
//            //  寻址到文件末尾
//            self.fileHandle?.seekToEndOfFile()
//            self.fileHandle?.writeData(data)
//            self.downLoadingOffset += data.length
//            self.receiveVideoDataHandler?(task: self)
//            let thread = NSThread.currentThread()
//            print("线程 - \(thread)")
        }
    }
    
    public func connectionDidFinishLoading(_ connection: NSURLConnection) {
        func tmpPersistence() {
            isFinishLoad = true
            let fileName = url?.lastPathComponent
//            let movePath = audioDicPath.stringByAppendingPathComponent(fileName ?? "undefine.mp4")
            let movePath = StreamAudioConfig.audioDicPath + "/\(fileName ?? "undefine.mp4")"
            _ = try? FileManager.default.removeItem(atPath: movePath)
            
            var isSuccessful = true
            do { try FileManager.default.copyItem(atPath: StreamAudioConfig.tempPath, toPath: movePath) } catch {
                isSuccessful = false
                print("tmp文件持久化失败")
            }
            if isSuccessful {
                print("持久化文件成功！路径 - \(movePath)")
            }
        }
        
        if taskArr.count < 2 {
            tmpPersistence()
        }
        
        receiveVideoFinishHanlder?(self)
    }
    
    public func connection(_ connection: NSURLConnection, didFailWithError error: Error) {
        if error._code == -1001 && !once {   //  超时，1秒后重连一次
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(1 * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
                self.continueLoading()
            })
        }
        if error._code == -1009 {
            print("无网络连接")
        }
        receiveVideoFailHandler?(self,error as NSError)
    }
}

// MARK: - private functions
extension RequestTask {
    /**
     断线重连
     */
    fileprivate func continueLoading() {
        once = true
        guard let url = url else {return}
        var actualURLComponents = URLComponents.init(url: url, resolvingAgainstBaseURL: false)
        actualURLComponents?.scheme = "http"
        guard let URL = actualURLComponents?.url else {return}
        let request = NSMutableURLRequest(url: URL, cachePolicy: NSURLRequest.CachePolicy.reloadIgnoringCacheData, timeoutInterval: 20.0)
        request.addValue("bytes=\(downLoadingOffset)-\(videoLength - 1)", forHTTPHeaderField: "Range")
        connection?.cancel()
        connection = NSURLConnection(request: request as URLRequest, delegate: self, startImmediately: false)
        connection?.setDelegateQueue(OperationQueue.main)
        connection?.start()
    }
}

extension RequestTask {
    
    public func cancel() {
        //  1. 断开连接
        connection?.cancel()
        //  2. 关闭文件写入句柄
        fileHandle?.closeFile()
        //  3. 移除缓存
        _ = try? FileManager.default.removeItem(atPath: StreamAudioConfig.tempPath)
    }
}
