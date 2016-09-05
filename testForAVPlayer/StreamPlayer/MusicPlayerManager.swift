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

public class MusicPlayerManager: NSObject {
    
    
    //  public var status
    
    public var currentURL: NSURL? {
        get {
            guard let currentIndex = currentIndex, musicURLList = musicURLList where currentIndex < musicURLList.count else {return nil}
            return musicURLList[currentIndex]
        }
    }
    
    /**用于解决swift中enum无法被监听的问题*/
    dynamic public var statusRaw: Int = 0
    
    /**播放状态，用于需要获取播放器状态的地方KVO*/
    public var status: ManagerStatus = .Non {
        didSet {
            if oldValue != status {
                guard let stateChangeHandlerArray = self.stateChangeHandlerArray else {return}
                for callBack in stateChangeHandlerArray {
                    callBack?(state: status)
                }
            }
        }
    }
    /**播放进度*/
    public var progress: CGFloat {
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
    public var playTime: CGFloat = 0
    /**总时长*/
    public var playDuration: CGFloat = CGFloat.max {
        didSet {
            if playDuration != oldValue {
                configNowPlayingCenter()
            }
        }
    }
    /**缓冲时长*/
    public var tmpTime: CGFloat = 0
    
    public var playEndConsul: (()->())?
    /**强引用控制器，防止被销毁*/
    public var currentController: UIViewController?
    /**标识当前控制器的编号，防止控制器重复加载*/
    public var currentIdentify: String?
    /**防止多处为handler赋值导致覆盖*/
    private var stateChangeHandlerArray: [((state: ManagerStatus)->())?]?
    
    
    //  private status
    private var currentIndex: Int?
    private var playerModel: PlayModel = .Normal
    private var currentItem: AVPlayerItem? {
        get {
            if let currentURL = currentURL {
                let item = getPlayerItem(withURL: currentURL)
                return item
            } else {
                return nil
            }
        }
    }
    
    private var isLocationMusic: Bool = false
    private var musicURLList: [NSURL]?
    private var musicInfo: MusicBasicInfo?
    
    //  basic element
    public var player: AVPlayer?
    
    private var playerStatusObserver: NSObject?
    private var resourceLoader: RequestLoader = RequestLoader()
    private var currentAsset: AVURLAsset?
    private var progressCallBack: ((tmpProgress: Float?, playProgress: Float?)->())?
    
    public class var sharedInstance: MusicPlayerManager {
        struct Singleton {
            static let instance = MusicPlayerManager()
        }
        return Singleton.instance
    }
    
    public enum ManagerStatus: Int {
        case Non, LoadSongInfo, ReadyToPlay, Play, Pause, Stop
    }
    
    /**
     播放模式
     
     - Normal:       正常播放
     - RepeatSingle: 单曲循环
     */
    public enum PlayModel {
        case Normal, RepeatSingle
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
    public func play(musicURL: NSURL?) {
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
    
    public func play(musicURL: NSURL?, callBack: ((tmpProgress: Float?, playProgress: Float?)->())?) {
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
        if status == .Play {
            player?.seekToTime(kCMTimeZero)
        }
    }
    
    /**
     配置歌曲信息，以控制Now Playing Center显示
     */
    public func configMusicInfo(musicTitle: String, artist: String, coverImage: UIImage?) {
        var realImage = UIImage(named: "AppIcon")
        if coverImage != nil {realImage = coverImage!}
        musicInfo = MusicBasicInfo(title: musicTitle, artist: artist, coverImage: realImage!)
        
        configNowPlayingCenter()
    }
    
    /**
     设置歌曲状态改变时的回调
     */
    public func setStateChangeCallBack(callBack: (state: ManagerStatus)->()) {
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
        let fileManager = NSFileManager.defaultManager()
        var size: Float = 0
        guard let fileArray = try? fileManager.contentsOfDirectoryAtPath(StreamAudioConfig.audioDicPath) else {return 0}
        for component in fileArray {
            if !component.containsString("temp.mp4") {
                let fullPath = StreamAudioConfig.audioDicPath + "/" + component
                if fileManager.fileExistsAtPath(fullPath) {
                    guard let fileAttributeDic = try? fileManager.attributesOfItemAtPath(fullPath) else {break}
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
        let fileManager = NSFileManager.defaultManager()
        guard let fileArray = try? fileManager.contentsOfDirectoryAtPath(StreamAudioConfig.audioDicPath) else {return}
        for component in fileArray {
            if !component.containsString("temp.mp4") {
                let fullPath = StreamAudioConfig.audioDicPath + "/" + component
                if fileManager.fileExistsAtPath(fullPath) {
                    do { try fileManager.removeItemAtPath(fullPath) } catch {print("music data remove failure -- path -- \(fullPath)")}
                }
            }
        }
    }
}

// MARK: - private funcs
extension MusicPlayerManager {
    
    private func putMusicToArray(music URL: NSURL) {
        if musicURLList == nil {
            musicURLList = [URL]
        } else {
            musicURLList!.insert(URL, atIndex: 0)
        }
    }
    
    private func getIndexOfMusic(music URL: NSURL) -> Int? {
        let index = musicURLList?.indexOf(URL)
        return index
    }
    
    private func getNextIndex() -> Int? {
        if let musicURLList = musicURLList where musicURLList.count > 0 {
            if let currentIndex = currentIndex where currentIndex + 1 < musicURLList.count {
                return currentIndex + 1
            } else {
                return 0
            }
        } else {
            return nil
        }
    }
    
    private func getPreviousIndex() -> Int? {
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
    private func replayMusicList() {
        guard let musicURLList = musicURLList where musicURLList.count > 0 else {return}
        currentIndex = 0
        playMusicWithCurrentIndex()
    }
    /**
     播放当前音乐
     */
    private func playMusicWithCurrentIndex() {
        guard let currentURL = currentURL else {return}
        //  结束上一首
        endPlay()
        player = AVPlayer(playerItem: getPlayerItem(withURL: currentURL))
        observePlayingItem()
    }
    /**
     本地不存在，返回nil，否则返回本地URL
     */
    private func getLocationFilePath(url: NSURL) -> NSURL? {
        func fromBundle(url: NSURL) -> Bool {
            if url.absoluteString.containsString("file://") {
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
            if NSFileManager.defaultManager().fileExistsAtPath(path) {
                let url = NSURL.init(fileURLWithPath: path)
                return url
            } else {
                return nil
            }
        }
    }
    
    private func getPlayerItem(withURL musicURL: NSURL) -> AVPlayerItem {
        
        if let locationFile = getLocationFilePath(musicURL) {
            let item = AVPlayerItem(URL: locationFile)
            isLocationMusic = true
            return item
        } else {
            let playURL = resourceLoader.getURL(url: musicURL)!  //  转换协议头
            let asset = AVURLAsset(URL: playURL)
            isLocationMusic = false
            currentAsset = asset
            asset.resourceLoader.setDelegate(resourceLoader, queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
            let item = AVPlayerItem(asset: asset)
            return item
        }
    }
    
    private func setupPlayer(withURL musicURL: NSURL) {
        let songItem = getPlayerItem(withURL: musicURL)
        player = AVPlayer(playerItem: songItem)
    }
    
    private func playerPlay() {
        player?.play()
    }
    
    private func endPlay() {
        status = ManagerStatus.Stop
        player?.rate = 0
        removeObserForPlayingItem()
        player?.replaceCurrentItemWithPlayerItem(nil)
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
    
    private func configNowPlayingCenter() {
        var info = [String:NSObject]()
        if let musicInfo = musicInfo {
            info.updateValue(musicInfo.title, forKey: MPMediaItemPropertyTitle)
            info.updateValue(musicInfo.artist, forKey: MPMediaItemPropertyArtist)
            let artwork = MPMediaItemArtwork(image: musicInfo.coverImage)   //  设置图片
            info.updateValue(artwork, forKey: MPMediaItemPropertyArtwork)                   //  锁屏界面
        }
        info.updateValue("\(playTime)", forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)   //   当前播放时长
        info.updateValue("\(player?.rate ?? 0)", forKey: MPNowPlayingInfoPropertyPlaybackRate)            //   播放速度
        info.updateValue("\(playDuration)", forKey: MPMediaItemPropertyPlaybackDuration)          //   总时长
        MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = info
    }
}

// MARK: - observer for player status
extension MusicPlayerManager {
    
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        guard object is AVPlayerItem else {return}
        let item = object as! AVPlayerItem
        if keyPath == "status" {
            if item.status == AVPlayerItemStatus.ReadyToPlay {
                status = .ReadyToPlay
                playerPlay()
            } else if item.status == AVPlayerItemStatus.Failed {
                stop()
            }
        } else if keyPath == "loadedTimeRanges" {
            let array = item.loadedTimeRanges
            guard let timeRange = array.first?.CMTimeRangeValue else {return}  //  缓冲时间范围
            let totalBuffer = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration)    //  当前缓冲长度
            tmpTime = CGFloat(totalBuffer)
            let tmpProgress = tmpTime / playDuration
            progressCallBack?(tmpProgress: Float(tmpProgress), playProgress: nil)
        }
    }
    
    private func observePlayingItem() {
        
        func dealForEnded() {
            switch playerModel {
            case .Normal:
                endPlay()
            case .RepeatSingle:
                rebroadcast()
            }
        }
        
        guard let currentItem = self.player?.currentItem else {return}
        //  KVO监听正在播放的对象状态变化
        currentItem.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.New, context: nil)
        //  监听player播放情况
        playerStatusObserver = player?.addPeriodicTimeObserverForInterval(CMTimeMake(1, 1), queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), usingBlock: { [weak self] (time) in
            guard let `self` = self else {return}
            //  获取当前播放时间
            self.status = .Play
            let currentTime = CMTimeGetSeconds(time)
            let totalTime = CMTimeGetSeconds(currentItem.duration)
            self.playDuration = CGFloat(totalTime)
            self.playTime = CGFloat(currentTime)
            let tmpProgress: Float? = self.isLocationMusic ? 1 : nil    //  本地播放，则返回tmp进度
            self.progressCallBack?(tmpProgress: tmpProgress, playProgress: Float(self.progress))
            if totalTime - currentTime < 0.1 {
                dealForEnded()
            }
            }) as? NSObject
        //  监听缓存情况
        currentItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.New, context: nil)
    }
    
    private func removeObserForPlayingItem() {
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
    
    private func configAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("启动后台模式失败，error -- \(error)")
        }
    }
    
    //  监听打断
    private func configBreakObserver() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleInterruption), name: AVAudioSessionInterruptionNotification, object: AVAudioSession.sharedInstance())
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSessionRouteChangeNotification, object: AVAudioSession.sharedInstance())
    }
    
    //  来电打断
    @objc private func handleInterruption(noti: NSNotification) {
        guard noti.name == AVAudioSessionInterruptionNotification else { return }
        guard let info = noti.userInfo, typenumber = info[AVAudioSessionInterruptionTypeKey]?.unsignedIntegerValue, type = AVAudioSessionInterruptionType(rawValue: typenumber) else { return }
        switch type {
        case .Began:
            pause()
        case .Ended:
            goOn()
        }
    }
    
    //拔出耳机等设备变更操作
    @objc private func handleRouteChange(noti: NSNotification) {
        
        func analysisInputAndOutputPorts(noti: NSNotification) {
            guard let info = noti.userInfo, previousRoute = info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            let inputs = previousRoute.inputs
            let outputs = previousRoute.outputs
            print(inputs)
            print(outputs)
        }
        
        guard noti.name == AVAudioSessionRouteChangeNotification else { return }
        guard let info = noti.userInfo, typenumber = info[AVAudioSessionRouteChangeReasonKey]?.unsignedIntegerValue, type = AVAudioSessionRouteChangeReason(rawValue: typenumber) else { return }
        switch type {
        case .Unknown:
            break
        case .NewDeviceAvailable:
            break
        case .OldDeviceUnavailable:
            break
        case .CategoryChange:
            break
        case .Override:
            break
        case .WakeFromSleep:
            break
        case .NoSuitableRouteForCategory:
            break
        case .RouteConfigurationChange:
            break
        }
    }
}

public struct StreamAudioConfig {
    static let audioDicPath: String = NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory.DocumentDirectory, NSSearchPathDomainMask.UserDomainMask, true).last! + "/streamAudio"  //  缓冲文件夹
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
public class BackgroundTask {
    
    private static var _counter: NSTimer?
    
    private static var _taskId: UIBackgroundTaskIdentifier = UIBackgroundTaskInvalid
    
    private static var _remainingTimeHandler: ((remainingTime: NSTimeInterval)->())?
    
    private static let _remainTimeRange = (min:Double(170), max:Double(171))
    
    private static let _remainTimeMax = Double(180)
    
    /**
     需要在 - func applicationDidEnterBackground(application: UIApplication) 方法中调用
     */
    public static func fire() {
        _startBackgroundMode { (remainingTime) in
            print(remainingTime)
            if remainingTime > _remainTimeMax {
                //  正在播放音乐或进入前台
            } else if remainingTime > _remainTimeRange.min && remainingTime < _remainTimeRange.max {
                _playBlankMusic()
            }
        }
        
        NSNotificationCenter.defaultCenter().addObserverForName(UIApplicationWillEnterForegroundNotification, object: nil, queue: NSOperationQueue.mainQueue()) { (noty) in
            _removeTimer()
        }
    }
    
    private static func _startBackgroundMode(handler: ((remainingTime: NSTimeInterval)->())?) {
        _remainingTimeHandler = handler
        _startWithExpirationHandler {
            print("App has been suspend")
        }
        _timingForRemaining()
    }
    
    private static func _timingForRemaining() {
        _removeTimer()
        _counter = NSTimer.scheduledTimerWithTimeInterval(1, target: self, selector: #selector(_dealWithRestBackgroundTime), userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(_counter!, forMode: NSDefaultRunLoopMode)
        _counter?.fire()
    }
    
    dynamic private static func _dealWithRestBackgroundTime() {
        let remainingTime = UIApplication.sharedApplication().backgroundTimeRemaining
        _remainingTimeHandler?(remainingTime: remainingTime)
    }
    
    private static func _startWithExpirationHandler(handler: (() -> Void)?) -> Bool {
        _taskId = UIApplication.sharedApplication().beginBackgroundTaskWithExpirationHandler {
            if let safeHandler = handler { safeHandler() }
            _endBackgroundTask()
        }
        return  (_taskId != UIBackgroundTaskInvalid)
    }
    
    private static func _endBackgroundTask() {
        if (_taskId != UIBackgroundTaskInvalid) {
            let id = _taskId
            _taskId = UIBackgroundTaskInvalid
            _removeTimer()
            UIApplication.sharedApplication().endBackgroundTask(id)
        }
    }
    
    private static func _playBlankMusic() {
        let bundlePath = NSBundle.mainBundle().pathForResource("Sounds", ofType: "bundle") ?? ""
        let bundle = NSBundle(path: bundlePath)
        let path = bundle?.pathForResource("blankMusic", ofType: "mp3")
        let url = NSURL.fileURLWithPath(path ?? "")
        MusicPlayerManager.sharedInstance.play(url)
    }
    
    private static func _removeTimer() {
        _counter?.invalidate()
        _counter = nil
    }
}