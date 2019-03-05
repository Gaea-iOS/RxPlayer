//
//  AVPlayerItem+Rx.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/2/26.
//

import RxSwift
import AVFoundation

extension Reactive where Base: AVPlayerItem {

    var status: Observable<AVPlayerItem.Status> {
        return observe(AVPlayerItem.Status.self, #keyPath(AVPlayer.status))
            .map { $0 ?? .unknown }
    }
    
    var didPlayToEnd: Observable<Notification> {
        return NotificationCenter.default.rx.notification(.AVPlayerItemDidPlayToEndTime, object: base)
    }

    var duration: Observable<CMTime> {
        return observe(CMTime.self, #keyPath(AVPlayerItem.duration))
            .map { $0 ?? .zero }
    }

    var isPlaybackBufferEmpty: Observable<Bool> {
        return observe(Bool.self, #keyPath(AVPlayerItem.isPlaybackBufferEmpty))
            .map { $0 ?? false }
    }

    var isPlaybackLikelyToKeepUp: Observable<Bool> {
        return observe(Bool.self, #keyPath(AVPlayerItem.isPlaybackLikelyToKeepUp))
            .map { $0 ?? false }
    }

    var loadedTimeRanges: Observable<[NSValue]> {
        return observe([NSValue].self, #keyPath(AVPlayerItem.loadedTimeRanges))
            .map { $0 ?? [] }
    }
}

extension Reactive where Base: AVAsset {

    var isPlayable: Observable<Bool> {
        return Observable.create { [unowned base] observer in
            base.loadValuesAsynchronously(forKeys: ["playable"]) {
                DispatchQueue.main.async {
                    var error: NSError?
                    let keyStatus = base.statusOfValue(forKey: "playable", error: &error)
                    if keyStatus == AVKeyValueStatus.failed || !base.isPlayable {
                        observer.onNext(false)
                    } else {
                        observer.onNext(true)
                    }
                }
            }
            return Disposables.create()
        }
    }
}
