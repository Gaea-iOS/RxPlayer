//
//  RxPlayer+BackgroundMode.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/25.
//

import RxSwift
import AVFoundation

extension RxPlayer {

    func enableBackgroundMode(applicationDidEnterBackground: Observable<()>,
                              applicationWillEnterForeground: Observable<()>) {

        item
            .mapToVoid()
            .subscribe(onNext: {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .default, options: [])
                try? session.setActive(true)
            })
            .disposed(by: disposeBag)

        applicationDidEnterBackground
            .withLatestFrom(isPlaying)
            .filterTrue()
            .mapToVoid()
            .subscribe(onNext: {
                BackgroundTaskCreator.shared.beginBackgroundTask()
            })
            .disposed(by: disposeBag)

        applicationWillEnterForeground
            .subscribe(onNext: {
                BackgroundTaskCreator.shared.endBackgroundTask()
            })
            .disposed(by: disposeBag)
    }
}
