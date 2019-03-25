//
//  PlayerItem.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import AVFoundation

public protocol PlayerItem: Equatable {
    var playURL: URL { get }
}

extension PlayerItem {
    var toAVPlayerItem: AVPlayerItem {
        return AVPlayerItem(url: playURL)
    }
}
