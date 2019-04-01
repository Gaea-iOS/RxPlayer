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

public enum RxPlayerStatus: String {
    case unknown
    case readyToPlay
    case failed
}

public class RxPlayer<T: PlayerItem> {

    public var isAutoPlay: Bool = true

    private let isAutoPlayWhenSeek: Bool = true
    
    public let item = PublishSubject<T>()

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

    public var progress: Observable<Float> {
        return playedTime
            .withLatestFrom(duration) { (playedTime: $0, duration: $1) }
            .map { $0.duration == 0 ? 0 : Float($0.playedTime / $0.duration) }
    }

    public var loadTimeRanges: Observable<[CMTimeRange]> {
        return _loadTimeRanges.asObservable()
    }

    public var didPlayToEndTime: Observable<()> {
        return _didPlayToEndTime.asObservable()
    }

    public let _status = BehaviorRelay(value: RxPlayerStatus.unknown)

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

    let disposeBag = DisposeBag()

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
                    self.stop()
                })
                .map { $0.toAVPlayerItem }
                .subscribe(onNext: { [unowned self] in
                    self._playerItem.accept($0)
                    if self.isAutoPlay {
                        self.play()
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

            seek
                .filter { !$0.isNaN || $0.isInfinite }
                .map { CMTime(timeInterval: $0) }
                .subscribe(onNext: { [unowned self] in
                    self._isSeeking.accept(true)
                    if self.isAutoPlayWhenSeek {
                        self.play()
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
                    .filterFalse(),

                _isPlaybackLikelyToKeepUp
                    .distinctUntilChanged()
                    .skip(1)
                    .filterTrue()
                )
                .mapToVoid()
                .do(onNext: { [unowned self] in
                    self.isItemReloadNeeded = true
                })
                .withLatestFrom(_isPlaying)
                .filterTrue()
                .mapToVoid()
                .subscribe(onNext: { [unowned self] in
                    self.play()
                })
                .disposed(by: disposeBag)
        }
    }
}


extension RxPlayer {

    public func play() {

        guard let playerItem = _playerItem.value else {
            return
        }

        if playerItem.status == .failed {

            Observable.just(())
                .withLatestFrom(item)
                .map { $0.toAVPlayerItem }
                .bind(to: _playerItem)
                .disposed(by: disposeBag)

            isItemReloadNeeded = true
        }

        if isItemReloadNeeded {
            player.replaceCurrentItem(with: nil)
            isItemReloadNeeded = false
        }

        player.replaceCurrentItem(with: _playerItem.value)

        player.play()
        _isPlaying.accept(true)
    }

    public func pause() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        _isPlaying.accept(false)
    }

    public func stop() {
        pause()
        _playerItem.accept(nil)
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
            DispatchQueue.main.async { self.pause() }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { break }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            DispatchQueue.main.async { options.contains(.shouldResume) ? self.play() : self.pause() }
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
            DispatchQueue.main.async { headphonesConnected ? () : self.pause() }
        default: break
        }
    }
}


extension AVPlayer.Status {
    func toRxPlayerStatus() -> RxPlayerStatus {
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
    func toRxPlayerStatus() -> RxPlayerStatus {
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

