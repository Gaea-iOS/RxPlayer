//
//  CMTime+Extension.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import AVFoundation

extension CMTime {

    init(timeInterval: TimeInterval) {
        self.init(value: CMTimeValue(timeInterval), timescale: 1)
    }

    var timeIntervalValue: TimeInterval {
        return CMTimeGetSeconds(self)
    }
}
