//
//  AppDelegate.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/10.
//  Copyright © 2016年 ymh. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        UIApplication.shared.beginReceivingRemoteControlEvents()
        becomeFirstResponder()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        BackgroundTask.fire()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    override var canBecomeFirstResponder : Bool {
        return true
    }
    
    override func remoteControlReceived(with event: UIEvent?) {
        guard let eventType = event?.subtype else {return}
        switch eventType {
        case .none:
            break
        case .motionShake:
            break
        case .remoteControlPlay:
            //  继续播放
            MusicPlayerManager.sharedInstance.goOn()
        case .remoteControlPause:
            MusicPlayerManager.sharedInstance.pause()
        case .remoteControlStop:
            MusicPlayerManager.sharedInstance.stop()
        case .remoteControlTogglePlayPause:
            //  耳机的播放、暂停按钮
            if MusicPlayerManager.sharedInstance.player?.rate == 0 {
                MusicPlayerManager.sharedInstance.goOn()
            } else {
                MusicPlayerManager.sharedInstance.pause()
            }
        case .remoteControlNextTrack:
            break
        case .remoteControlPreviousTrack:
            break
        case .remoteControlBeginSeekingBackward:
            break
        case .remoteControlEndSeekingBackward:
            break
        case .remoteControlBeginSeekingForward:
            break
        case .remoteControlEndSeekingForward:
            break
        }
    }

}

