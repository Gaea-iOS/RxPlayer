//
//  RxPlayer.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/2/18.
//

import RxSwift
import RxCocoa
import RxSwiftExt
import AVFoundation
import Reachability
import RxReachability
import RxAppState

public class RxPlayer {

    public enum Status: String {
        case unknown
        case readyToPlay
        case failed
    }

    public let isAutoPlay: Bool = true

    public let isAutoPlayWhenSeek: Bool = true
    
    public let item = BehaviorRelay<PlayerItem?>(value: nil)

    public let play = PublishSubject<()>()

    public let pause = PublishSubject<()>()

    public let seek = PublishSubject<TimeInterval>()

    public var isPlaying: Observable<Bool> {
        return _isPlaying.distinctUntilChanged()
    }

    public var isPlaybackLikelyToKeepUp: Observable<Bool> {
        return _isPlaybackLikelyToKeepUp.distinctUntilChanged()
    }

    public var isSeeking: Observable<Bool> {
        return _isSeeking.distinctUntilChanged()
    }

    public var duration: Observable<TimeInterval> {
        return _duration.asObservable()
    }

    public var playedTime: Observable<TimeInterval> {
        return _playedTime.asObservable()
    }

    public var loadTimeRanges: Observable<[CMTimeRange]> {
        return _loadTimeRanges.asObservable()
    }

    public var didPlayToEndTime: Observable<()> {
        return _didPlayToEndTime.asObservable()
    }

    public let _status = BehaviorRelay(value: Status.unknown)

    private let _isPlaying = BehaviorRelay(value: false)

    private let _isPlaybackLikelyToKeepUp = BehaviorRelay(value: false)

    private let _isSeeking = BehaviorRelay(value: false)

    private let _duration = BehaviorRelay(value: TimeInterval(0.0))

    private let _playedTime = BehaviorRelay(value: TimeInterval(0.0))

    private let _loadTimeRanges = BehaviorRelay(value: [CMTimeRange]())

    private let _didPlayToEndTime = PublishSubject<()>()

    private let player = AVPlayer()

    private let _playerItem = BehaviorRelay<AVPlayerItem?>(value: nil)

    private var isItemReloadNeeded: Bool = false

    private let reachability = Reachability()!

    private let disposeBag = DisposeBag()

    private var isBackgroundModeEnabled = true

    private var backgroundTaskCreator = BackgroundTaskCreator()

    public init() {

        NotificationCenter.default.rx
            .notification(AVAudioSession.interruptionNotification)
            .subscribe(onNext: { [unowned self] in
                self.handleInterruption(notification: $0)
            })
            .disposed(by: disposeBag)

        NotificationCenter.default.rx
            .notification(AVAudioSession.routeChangeNotification)
            .subscribe(onNext: { [unowned self] in
                self.handleRouteChange(notification: $0)
            })
            .disposed(by: disposeBag)

        try? reachability.startNotifier()

        do {
            player.rx
                .periodicTimeObserver(interval: CMTime(value: 1, timescale: 1000))
                .map { $0.timeIntervalValue }
                .bind(to: _playedTime)
                .disposed(by: disposeBag)
        }

        do {
            item
                .do(onNext: { [unowned self] _ in
                    self.pause.onNext(())
                })
                .map { $0?.toAVPlayerItem }
                .subscribe(onNext: { [unowned self] in
                    self._playerItem.accept($0)
                    if self.isAutoPlay {
                        self.play.onNext(())
                    }
                })
                .disposed(by: disposeBag)
        }

        do {

            let playerItem = _playerItem.unwrap().share()

            playerItem
                .flatMapLatest { $0.rx.didPlayToEnd }
                .mapToVoid()
                .bind(to: _didPlayToEndTime)
                .disposed(by: disposeBag)

            playerItem
                .flatMapLatest { $0.rx.duration }
                .map { $0.timeIntervalValue }
                .bind(to: _duration)
                .disposed(by: disposeBag)

            playerItem
                .flatMapLatest { $0.rx.isPlaybackLikelyToKeepUp }
                .bind(to: _isPlaybackLikelyToKeepUp)
                .disposed(by: disposeBag)

            playerItem
                .flatMapLatest { $0.rx.loadedTimeRanges }
                .map { $0.compactMap { $0.timeRangeValue } }
                .bind(to: _loadTimeRanges)
                .disposed(by: disposeBag)

            playerItem
                .flatMapLatest { $0.rx.status }
                .map { $0.toRxPlayerStatus() }
                .bind(to: _status)
                .disposed(by: disposeBag)
        }

        do {

            play
                .subscribe(onNext: { [unowned self] in
                    self.tryToPlay()
                })
                .disposed(by: disposeBag)

            pause
                .subscribe(onNext: { [unowned self] in
                    self.stopPlay()
                })
                .disposed(by: disposeBag)

            seek
                .filter { !$0.isNaN || $0.isInfinite }
                .map { CMTime(timeInterval: $0) }
                .subscribe(onNext: { [unowned self] in
                    self._isSeeking.accept(true)
                    if self.isAutoPlayWhenSeek {
                        self.play.onNext(())
                    }
                    self.player.seek(to: $0, completionHandler: { [unowned self] _ in
                        self._isSeeking.accept(false)
                    })
                })
                .disposed(by: disposeBag)
        }

        do {

            Observable.merge(
                reachability.rx
                    .isReachable
                    .distinctUntilChanged()
                    .skip(1)
                    .filterTrue()
                    .withLatestFrom(_isPlaybackLikelyToKeepUp)
                    .filterFalse()
                    .debug("isReachable"),

                _isPlaybackLikelyToKeepUp
                    .distinctUntilChanged()
                    .skip(1)
                    .filterTrue()
                    .debug("_isPlaybackLikelyToKeepUp")
                )
                .mapToVoid()
                .do(onNext: { [unowned self] in
                    self.isItemReloadNeeded = true
                })
                .withLatestFrom(_isPlaying)
                .filterTrue()
                .mapToVoid()
                .subscribe(onNext: { [unowned self] in
                    self.tryToPlay()
                })
                .disposed(by: disposeBag)
        }

        do {

            UIApplication.shared.beginReceivingRemoteControlEvents()

            item
                .subscribe(onNext: {
                    let session = AVAudioSession.sharedInstance()
                    try? session.setCategory(.playback, mode: .default, options: [])
                    try? session.setActive($0 == nil ? false : true)
                })
                .disposed(by: disposeBag)

            UIApplication.shared.rx
                .applicationDidEnterBackground
                .withLatestFrom(_isPlaying)
                .filterTrue()
                .subscribe(onNext: { [unowned self] _ in
                    self.isBackgroundModeEnabled ? self.backgroundTaskCreator.beginBackgroundTask() : ()
                })
                .disposed(by: disposeBag)

            UIApplication.shared.rx
                .applicationWillEnterForeground
                .subscribe(onNext: { [unowned self] _ in
                    self.backgroundTaskCreator.endBackgroundTask()
                })
                .disposed(by: disposeBag)
        }
    }
}


extension RxPlayer {

    private func tryToPlay() {

        guard let playerItem = _playerItem.value else {
            return
        }

        if playerItem.status == .failed,
            let newPlayerItem = item.value?.toAVPlayerItem {
            _playerItem.accept(newPlayerItem)
            isItemReloadNeeded = true
        }

        if isItemReloadNeeded {
            player.replaceCurrentItem(with: nil)
            isItemReloadNeeded = false
        }

        player.replaceCurrentItem(with: _playerItem.value)

        player.play()
        _isPlaying.accept(true)

        if isBackgroundModeEnabled {
            backgroundTaskCreator.beginBackgroundTask()
        }
    }

    private func stopPlay() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        _isPlaying.accept(false)

        backgroundTaskCreator.endBackgroundTask()
    }
}

extension RxPlayer {

    private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }

        switch type {
        case .began:
            DispatchQueue.main.async { self.pause.onNext(()) }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { break }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            DispatchQueue.main.async { options.contains(.shouldResume) ? self.play.onNext(()) : self.pause.onNext(()) }
        }
    }

    private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
            let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            guard let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
            let headphonesConnected = previousRoute.outputs.map { $0.portType }.contains(.headphones)
            DispatchQueue.main.async { headphonesConnected ? () : self.pause.onNext(()) }
        default: break
        }
    }
}


extension AVPlayer.Status {
    func toRxPlayerStatus() -> RxPlayer.Status {
        switch self {
        case .unknown:
            return .unknown
        case .failed:
            return .failed
        case .readyToPlay:
            return .readyToPlay
        }
    }
}

extension AVPlayerItem.Status {
    func toRxPlayerStatus() -> RxPlayer.Status {
        switch self {
        case .unknown:
            return .unknown
        case .failed:
            return .failed
        case .readyToPlay:
            return .readyToPlay
        }
    }
}

