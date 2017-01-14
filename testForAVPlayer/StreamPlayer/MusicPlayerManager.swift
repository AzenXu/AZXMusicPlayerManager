//
//  MusicPlayerManager.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/10.
//  Copyright © 2016年 ymh. All rights reserved.
//
//  TODO: 断点下载、线程优化、支持视频流播放

import AVFoundation
import MediaPlayer

open class MusicPlayerManager: NSObject {
    
    
    //  public var status
    
    open var currentURL: URL? {
        get {
            guard let currentIndex = currentIndex, let musicURLList = musicURLList, currentIndex < musicURLList.count else {return nil}
            return musicURLList[currentIndex]
        }
    }
    
    /**用于解决swift中enum无法被监听的问题*/
    dynamic open var statusRaw: Int = 0
    
    /**播放状态，用于需要获取播放器状态的地方KVO*/
    open var status: ManagerStatus = .non {
        didSet {
            if oldValue != status {
                guard let stateChangeHandlerArray = self.stateChangeHandlerArray else {return}
                for callBack in stateChangeHandlerArray {
                    callBack?(status)
                }
            }
        }
    }
    /**播放进度*/
    open var progress: CGFloat {
        get {
            if playDuration > 0 {
                let progress = playTime / playDuration
                return progress
            } else {
                return 0
            }
        }
    }
    /**已播放时长*/
    open var playTime: CGFloat = 0
    /**总时长*/
    open var playDuration: CGFloat = CGFloat.greatestFiniteMagnitude {
        didSet {
            if playDuration != oldValue {
                configNowPlayingCenter()
            }
        }
    }
    /**缓冲时长*/
    open var tmpTime: CGFloat = 0
    
    open var playEndConsul: (()->())?
    /**强引用控制器，防止被销毁*/
    open var currentController: UIViewController?
    /**标识当前控制器的编号，防止控制器重复加载*/
    open var currentIdentify: String?
    /**防止多处为handler赋值导致覆盖*/
    fileprivate var stateChangeHandlerArray: [((_ state: ManagerStatus)->())?]?
    
    
    //  private status
    fileprivate var currentIndex: Int?
    fileprivate var playerModel: PlayModel = .normal
    fileprivate var currentItem: AVPlayerItem? {
        get {
            if let currentURL = currentURL {
                let item = getPlayerItem(withURL: currentURL)
                return item
            } else {
                return nil
            }
        }
    }
    
    fileprivate var isLocationMusic: Bool = false
    fileprivate var musicURLList: [URL]?
    fileprivate var musicInfo: MusicBasicInfo?
    
    //  basic element
    open var player: AVPlayer?
    
    fileprivate var playerStatusObserver: NSObject?
    fileprivate var resourceLoader: RequestLoader = RequestLoader()
    fileprivate var currentAsset: AVURLAsset?
    fileprivate var progressCallBack: ((_ tmpProgress: Float?, _ playProgress: Float?)->())?
    
    open class var sharedInstance: MusicPlayerManager {
        struct Singleton {
            static let instance = MusicPlayerManager()
        }
        return Singleton.instance
    }
    
    public enum ManagerStatus: Int {
        case non, loadSongInfo, readyToPlay, play, pause, stop
    }
    
    /**
     播放模式
     
     - Normal:       正常播放
     - RepeatSingle: 单曲循环
     */
    public enum PlayModel {
        case normal, repeatSingle
    }
    
    /**
     *  Now Playing Center Model
     */
    struct MusicBasicInfo {
        var title: String
        var artist: String
        var coverImage: UIImage
        
        init(title: String, artist: String, coverImage: UIImage) {
            self.title = title
            self.artist = artist
            self.coverImage = coverImage
        }
    }
}

// MARK: - basic public funcs
extension MusicPlayerManager {
    /**
     开始播放
     */
    public func play(_ musicURL: URL?) {
        guard let musicURL = musicURL else {return}
        if let index = getIndexOfMusic(music: musicURL) {   //   歌曲在队列中，则按顺序播放
            currentIndex = index
        } else {
            putMusicToArray(music: musicURL)
            currentIndex = 0
        }
        playMusicWithCurrentIndex()
        configNowPlayingCenter()
        configAudioSession()
        configBreakObserver()
    }
    
    public func play(_ musicURL: URL?, callBack: ((_ tmpProgress: Float?, _ playProgress: Float?)->())?) {
        play(musicURL)
        progressCallBack = callBack
    }
    
    public func next() {
        currentIndex = getNextIndex()
        playMusicWithCurrentIndex()
    }
    
    public func previous() {
        currentIndex = getPreviousIndex()
        playMusicWithCurrentIndex()
    }
    /**
     继续
     */
    public func goOn() {
        player?.rate = 1
        configNowPlayingCenter()
    }
    /**
     暂停 - 可继续
     */
    public func pause() {
        player?.rate = 0
        configNowPlayingCenter()
    }
    /**
     停止 - 无法继续
     */
    public func stop() {
        endPlay()
        musicInfo = nil
        configNowPlayingCenter()
    }
    
    public func rebroadcast() {
        if status == .play {
            player?.seek(to: kCMTimeZero)
        }
    }
    
    /**
     配置歌曲信息，以控制Now Playing Center显示
     */
    public func configMusicInfo(_ musicTitle: String, artist: String, coverImage: UIImage?) {
        var realImage = UIImage(named: "AppIcon")
        if coverImage != nil {realImage = coverImage!}
        musicInfo = MusicBasicInfo(title: musicTitle, artist: artist, coverImage: realImage!)
        
        configNowPlayingCenter()
    }
    
    /**
     设置歌曲状态改变时的回调
     */
    public func setStateChangeCallBack(_ callBack: @escaping (_ state: ManagerStatus)->()) {
        if stateChangeHandlerArray != nil {
            stateChangeHandlerArray?.append(callBack)
        } else {
            stateChangeHandlerArray = [callBack]
        }
    }
    
    /**
     获取歌曲缓存文件夹大小
     
     - returns: 返回值大小单位：KB
     */
    public func getMusicDirSize() -> Float {
        let fileManager = FileManager.default
        var size: Float = 0
        guard let fileArray = try? fileManager.contentsOfDirectory(atPath: StreamAudioConfig.audioDicPath) else {return 0}
        for component in fileArray {
            if !component.contains("temp.mp4") {
                let fullPath = StreamAudioConfig.audioDicPath + "/" + component
                if fileManager.fileExists(atPath: fullPath) {
                    guard let fileAttributeDic = try? fileManager.attributesOfItem(atPath: fullPath) else {break}
                    let fileSize = fileAttributeDic["NSFileSize"] as? Float ?? 0
                    size += (fileSize/1024.0)
                }
            }
        }
        return size
    }
    /**
     清空歌曲缓存文件夹
     */
    public func clearMusicDir() {
        let fileManager = FileManager.default
        guard let fileArray = try? fileManager.contentsOfDirectory(atPath: StreamAudioConfig.audioDicPath) else {return}
        for component in fileArray {
            if !component.contains("temp.mp4") {
                let fullPath = StreamAudioConfig.audioDicPath + "/" + component
                if fileManager.fileExists(atPath: fullPath) {
                    do { try fileManager.removeItem(atPath: fullPath) } catch {print("music data remove failure -- path -- \(fullPath)")}
                }
            }
        }
    }
}

// MARK: - private funcs
extension MusicPlayerManager {
    
    fileprivate func putMusicToArray(music URL: Foundation.URL) {
        if musicURLList == nil {
            musicURLList = [URL]
        } else {
            musicURLList!.insert(URL, at: 0)
        }
    }
    
    fileprivate func getIndexOfMusic(music URL: Foundation.URL) -> Int? {
        let index = musicURLList?.index(of: URL)
        return index
    }
    
    fileprivate func getNextIndex() -> Int? {
        if let musicURLList = musicURLList, musicURLList.count > 0 {
            if let currentIndex = currentIndex, currentIndex + 1 < musicURLList.count {
                return currentIndex + 1
            } else {
                return 0
            }
        } else {
            return nil
        }
    }
    
    fileprivate func getPreviousIndex() -> Int? {
        if let currentIndex = currentIndex {
            if currentIndex - 1 >= 0 {
                return currentIndex - 1
            } else {
                return musicURLList?.count ?? 1 - 1
            }
        } else {
            return nil
        }
    }
    
    /**
     从头播放音乐列表
     */
    fileprivate func replayMusicList() {
        guard let musicURLList = musicURLList, musicURLList.count > 0 else {return}
        currentIndex = 0
        playMusicWithCurrentIndex()
    }
    /**
     播放当前音乐
     */
    fileprivate func playMusicWithCurrentIndex() {
        guard let currentURL = currentURL else {return}
        //  结束上一首
        endPlay()
        player = AVPlayer(playerItem: getPlayerItem(withURL: currentURL))
        observePlayingItem()
    }
    /**
     本地不存在，返回nil，否则返回本地URL
     */
    fileprivate func getLocationFilePath(_ url: URL) -> URL? {
        func fromBundle(_ url: URL) -> Bool {
            if url.absoluteString.contains("file://") {
                return true
            } else {
                return false
            }
        }
        
        if fromBundle(url) {
            return url
        } else {    //  from cache
            let fileName = url.lastPathComponent
            let path = StreamAudioConfig.audioDicPath + "/\(fileName ?? "tmp.mp4")"
            if FileManager.default.fileExists(atPath: path) {
                let url = URL.init(fileURLWithPath: path)
                return url
            } else {
                return nil
            }
        }
    }
    
    fileprivate func getPlayerItem(withURL musicURL: URL) -> AVPlayerItem {
        
        if let locationFile = getLocationFilePath(musicURL) {
            let item = AVPlayerItem(url: locationFile)
            isLocationMusic = true
            return item
        } else {
            let playURL = resourceLoader.getURL(url: musicURL)!  //  转换协议头
            let asset = AVURLAsset(url: playURL)
            isLocationMusic = false
            currentAsset = asset
            asset.resourceLoader.setDelegate(resourceLoader, queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default))
            let item = AVPlayerItem(asset: asset)
            return item
        }
    }
    
    fileprivate func setupPlayer(withURL musicURL: URL) {
        let songItem = getPlayerItem(withURL: musicURL)
        player = AVPlayer(playerItem: songItem)
    }
    
    fileprivate func playerPlay() {
        player?.play()
    }
    
    fileprivate func endPlay() {
        status = ManagerStatus.stop
        player?.rate = 0
        removeObserForPlayingItem()
        player?.replaceCurrentItem(with: nil)
        resourceLoader.cancel()
        currentAsset?.resourceLoader.setDelegate(nil, queue: nil)
        
        progressCallBack = nil
        resourceLoader = RequestLoader()
        playDuration = 0
        playTime = 0
        playEndConsul?()
        player = nil
        
        currentController = nil
        currentIdentify = nil
    }
    
    fileprivate func configNowPlayingCenter() {
        var info = [String:NSObject]()
        if let musicInfo = musicInfo {
            info.updateValue(musicInfo.title as NSObject, forKey: MPMediaItemPropertyTitle)
            info.updateValue(musicInfo.artist as NSObject, forKey: MPMediaItemPropertyArtist)
            let artwork = MPMediaItemArtwork(image: musicInfo.coverImage)   //  设置图片
            info.updateValue(artwork, forKey: MPMediaItemPropertyArtwork)                   //  锁屏界面
        }
        info.updateValue("\(playTime)" as NSObject, forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)   //   当前播放时长
        info.updateValue("\(player?.rate ?? 0)" as NSObject, forKey: MPNowPlayingInfoPropertyPlaybackRate)            //   播放速度
        info.updateValue("\(playDuration)" as NSObject, forKey: MPMediaItemPropertyPlaybackDuration)          //   总时长
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - observer for player status
extension MusicPlayerManager {
    
    open override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard object is AVPlayerItem else {return}
        let item = object as! AVPlayerItem
        if keyPath == "status" {
            if item.status == AVPlayerItemStatus.readyToPlay {
                status = .readyToPlay
                playerPlay()
            } else if item.status == AVPlayerItemStatus.failed {
                stop()
            }
        } else if keyPath == "loadedTimeRanges" {
            let array = item.loadedTimeRanges
            guard let timeRange = array.first?.timeRangeValue else {return}  //  缓冲时间范围
            let totalBuffer = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)    //  当前缓冲长度
            tmpTime = CGFloat(totalBuffer)
            let tmpProgress = tmpTime / playDuration
            progressCallBack?(Float(tmpProgress), nil)
        }
    }
    
    fileprivate func observePlayingItem() {
        
        func dealForEnded() {
            switch playerModel {
            case .normal:
                endPlay()
            case .repeatSingle:
                rebroadcast()
            }
        }
        
        guard let currentItem = self.player?.currentItem else {return}
        //  KVO监听正在播放的对象状态变化
        currentItem.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        //  监听player播放情况
        playerStatusObserver = player?.addPeriodicTimeObserver(forInterval: CMTimeMake(1, 1), queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.default), using: { [weak self] (time) in
            guard let `self` = self else {return}
            //  获取当前播放时间
            self.status = .play
            let currentTime = CMTimeGetSeconds(time)
            let totalTime = CMTimeGetSeconds(currentItem.duration)
            self.playDuration = CGFloat(totalTime)
            self.playTime = CGFloat(currentTime)
            let tmpProgress: Float? = self.isLocationMusic ? 1 : nil    //  本地播放，则返回tmp进度
            self.progressCallBack?(tmpProgress, Float(self.progress))
            if totalTime - currentTime < 0.1 {
                dealForEnded()
            }
            }) as? NSObject
        //  监听缓存情况
        currentItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    fileprivate func removeObserForPlayingItem() {
        guard let currentItem = self.player?.currentItem else {return}
        currentItem.removeObserver(self, forKeyPath: "status")
        if playerStatusObserver != nil {
            player?.removeTimeObserver(playerStatusObserver!)
            playerStatusObserver = nil
        }
        currentItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
    }
}

// MARK: - for AVAudioSession
extension MusicPlayerManager {
    
    fileprivate func configAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("启动后台模式失败，error -- \(error)")
        }
    }
    
    //  监听打断
    fileprivate func configBreakObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: NSNotification.Name.AVAudioSessionInterruption, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: NSNotification.Name.AVAudioSessionRouteChange, object: AVAudioSession.sharedInstance())
    }
    
    //  来电打断
    @objc fileprivate func handleInterruption(_ noti: Notification) {
        guard noti.name == NSNotification.Name.AVAudioSessionInterruption else { return }
        guard let info = noti.userInfo, let typenumber = (info[AVAudioSessionInterruptionTypeKey] as AnyObject).uintValue, let type = AVAudioSessionInterruptionType(rawValue: typenumber) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            goOn()
        }
    }
    
    //拔出耳机等设备变更操作
    @objc fileprivate func handleRouteChange(_ noti: Notification) {
        
        func analysisInputAndOutputPorts(_ noti: Notification) {
            guard let info = noti.userInfo, let previousRoute = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            let inputs = previousRoute.inputs
            let outputs = previousRoute.outputs
            print(inputs)
            print(outputs)
        }
        
        guard noti.name == NSNotification.Name.AVAudioSessionRouteChange else { return }
        guard let info = noti.userInfo, let typenumber = (info[AVAudioSessionRouteChangeReasonKey] as AnyObject).uintValue, let type = AVAudioSessionRouteChangeReason(rawValue: typenumber) else { return }
        switch type {
        case .unknown:
            break
        case .newDeviceAvailable:
            break
        case .oldDeviceUnavailable:
            break
        case .categoryChange:
            break
        case .override:
            break
        case .wakeFromSleep:
            break
        case .noSuitableRouteForCategory:
            break
        case .routeConfigurationChange:
            break
        }
    }
}

public struct StreamAudioConfig {
    static let audioDicPath: String = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true).last! + "/streamAudio"  //  缓冲文件夹
    static let tempPath: String = audioDicPath + "/temp.mp4"    //  缓冲文件路径 - 非持久化文件路径 - 当前逻辑下，有且只有一个缓冲文件
    
}

//MARK: - 常驻后台
/*
 *  原理：1. 向系统申请3分钟后台权限
 *       2. 3分钟快到期时，播放一段极短的空白音乐
 *       3. 播放结束之后，又有了3分钟的后台权限
 *
 *  备注：1. 其他音乐类App在播放时，无法被我们的空白音乐打断。如果3分钟内音乐未结束，我们的App会被真正挂起
 *       2. 其他音乐未播放时，我们的空白音乐有可能调起 - AVAudioSession进行控制
 */
open class BackgroundTask {
    
    fileprivate static var _counter: Timer?
    
    fileprivate static var _taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    fileprivate static var _remainingTimeHandler: ((_ remainingTime: TimeInterval)->())?
    
    fileprivate static let _remainTimeRange = (min:Double(170), max:Double(171))
    
    fileprivate static let _remainTimeMax = Double(180)
    
    /**
     需要在 - func applicationDidEnterBackground(application: UIApplication) 方法中调用
     */
    open static func fire() {
        _startBackgroundMode { (remainingTime) in
            print(remainingTime)
            if remainingTime > _remainTimeMax {
                //  正在播放音乐或进入前台
            } else if remainingTime > _remainTimeRange.min && remainingTime < _remainTimeRange.max {
                _playBlankMusic()
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: OperationQueue.main) { (noty) in
            _removeTimer()
        }
    }
    
    fileprivate static func _startBackgroundMode(_ handler: ((_ remainingTime: TimeInterval)->())?) {
        _remainingTimeHandler = handler
        _startWithExpirationHandler {
            print("App has been suspend")
        }
        _timingForRemaining()
    }
    
    fileprivate static func _timingForRemaining() {
        _removeTimer()
        _counter = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(_dealWithRestBackgroundTime), userInfo: nil, repeats: true)
        RunLoop.current.add(_counter!, forMode: RunLoopMode.defaultRunLoopMode)
        _counter?.fire()
    }
    
    dynamic fileprivate static func _dealWithRestBackgroundTime() {
        let remainingTime = UIApplication.shared.backgroundTimeRemaining
        _remainingTimeHandler?(remainingTime)
    }
    
    fileprivate static func _startWithExpirationHandler(_ handler: (() -> Void)?) -> Bool {
        _taskId = UIApplication.shared.beginBackgroundTask (expirationHandler: {
            if let safeHandler = handler { safeHandler() }
            _endBackgroundTask()
        })
        return  (_taskId != UIBackgroundTaskInvalid)
    }
    
    fileprivate static func _endBackgroundTask() {
        if (_taskId != UIBackgroundTaskInvalid) {
            let id = _taskId
            _taskId = UIBackgroundTaskInvalid
            _removeTimer()
            UIApplication.shared.endBackgroundTask(id)
        }
    }
    
    fileprivate static func _playBlankMusic() {
        let bundlePath = Bundle.main.path(forResource: "Sounds", ofType: "bundle") ?? ""
        let bundle = Bundle(path: bundlePath)
        let path = bundle?.path(forResource: "blankMusic", ofType: "mp3")
        let url = URL(fileURLWithPath: path ?? "")
        MusicPlayerManager.sharedInstance.play(url)
    }
    
    fileprivate static func _removeTimer() {
        _counter?.invalidate()
        _counter = nil
    }
}
