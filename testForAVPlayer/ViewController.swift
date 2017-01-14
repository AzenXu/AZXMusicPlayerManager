//
//  ViewController.swift
//  testForAVPlayer
//
//  Created by XuAzen on 16/8/10.
//  Copyright © 2016年 ymh. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {
    
    let urlStrings = ["http://m2.music.126.net/feplW2VPVs9Y8lE_I08BQQ==/1386484166585821.mp3",
                      "http://m2.music.126.net/dUZxbXIsRXpltSFtE7Xphg==/1375489050352559.mp3",
                      "http://m2.music.126.net/zLk1RXSKMONJye6jB3mjSA==/1407374887680902.mp3",
                      "http://audio.jiuxiulvxing.com/18路财神语音简介.mp3"]

    override func viewDidLoad() {
        super.viewDidLoad()
        let musicURL = URL.init(string: "http://m2.music.126.net/feplW2VPVs9Y8lE_I08BQQ==/1386484166585821.mp3")!
        MusicPlayerManager.sharedInstance.play(musicURL)
    }
    
    @IBAction func startPlay(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.play(MusicPlayerManager.sharedInstance.currentURL)
    }
    
    @IBAction func stop(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.stop()
    }
    
    @IBAction func pasue(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.pause()
    }
    
    @IBAction func goOn(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.goOn()
    }
    
    @IBAction func nextSong(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.next()
    }
    @IBAction func lastSong(_ sender: AnyObject) {
        MusicPlayerManager.sharedInstance.previous()
    }
    
    @IBAction func choiceSong(_ sender: UIButton) {
        guard sender.tag < urlStrings.count else {return}
        let urlString = urlStrings[sender.tag]
        let url = URL(string: urlString)
        MusicPlayerManager.sharedInstance.play(url)
    }
}
