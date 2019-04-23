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

    public let play = PublishSubject<()>()

    public let pause = PublishSubject<()>()

    public let seek = PublishSubject<TimeInterval>()

    public let rate = PublishSubject<Float>()

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

    private let _playerItem = PublishSubject<AVPlayerItem>()

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
                    self.pause.onNext(())
                })
                .map { $0.toAVPlayerItem }
                .do(onNext: { [unowned self] in
                    self._playerItem.onNext($0)
                })
                .mapToVoid()
                .filter { [unowned self] _ in self.isAutoPlay }
                .bind(to: play)
                .disposed(by: disposeBag)
        }

        do {

            _playerItem
                .flatMapLatest { $0.rx.didPlayToEnd }
                .mapToVoid()
                .bind(to: _didPlayToEndTime)
                .disposed(by: disposeBag)

            _playerItem
                .flatMapLatest { $0.rx.duration }
                .map { $0.timeIntervalValue }
                .bind(to: _duration)
                .disposed(by: disposeBag)

            _playerItem
                .flatMapLatest { $0.rx.isPlaybackLikelyToKeepUp }
                .bind(to: _isPlaybackLikelyToKeepUp)
                .disposed(by: disposeBag)

            _playerItem
                .flatMapLatest { $0.rx.loadedTimeRanges }
                .map { $0.compactMap { $0.timeRangeValue } }
                .bind(to: _loadTimeRanges)
                .disposed(by: disposeBag)

            _playerItem
                .flatMapLatest { $0.rx.status }
                .map { $0.toRxPlayerStatus() }
                .bind(to: _status)
                .disposed(by: disposeBag)
        }

        do {

            Observable.merge(
                play
                    .withLatestFrom(_playerItem)
                    .filter { $0.status != .failed },

                play
                    .withLatestFrom(_playerItem)
                    .filter { $0.status == .failed }
                    .withLatestFrom(item)
                    .map { $0.toAVPlayerItem }
                    .do(onNext: { [unowned self] playerItem in
                        self._playerItem.onNext(playerItem)
                        self.isItemReloadNeeded = true
                    })
                )
                .do(onNext: { [unowned self] playerItem in
                    if self.isItemReloadNeeded {
                        self.player.replaceCurrentItem(with: nil)
                        self.isItemReloadNeeded = false
                    }
                    self.player.replaceCurrentItem(with: playerItem)
                })
                .subscribe(onNext: { [unowned self] _ in
                    self.player.play()
                    self._isPlaying.accept(true)
                })
                .disposed(by: disposeBag)

            pause
                .subscribe(onNext: { [unowned self] in
                    self.player.pause()
                    self.player.replaceCurrentItem(with: nil)
                    self._isPlaying.accept(false)
                })
                .disposed(by: disposeBag)
        }

        do {

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

            rate
                .subscribe(onNext: { [unowned self] in
                    self.player.rate = $0
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
                    self.play.onNext(())
                })
                .disposed(by: disposeBag)
        }
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

