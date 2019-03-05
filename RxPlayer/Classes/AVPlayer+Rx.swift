//
//  AVPlayer+Rx.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/2/26.
//

import RxSwift
import AVFoundation

extension Reactive where Base: AVPlayer {

    var status: Observable<AVPlayer.Status> {
        return observe(AVPlayer.Status.self, #keyPath(AVPlayer.status))
            .map { $0 ?? .unknown }
    }
    
    func periodicTimeObserver(interval: CMTime) -> Observable<CMTime> {
        return Observable.create { observer in
            let time = self.base.addPeriodicTimeObserver(forInterval: interval, queue: nil) { time in
                observer.onNext(time)
            }
            return Disposables.create { self.base.removeTimeObserver(time) }
        }
    }
}
