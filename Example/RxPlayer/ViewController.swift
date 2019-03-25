//
//  ViewController.swift
//  PPPlayer
//
//  Created by wangxiaotao on 02/18/2019.
//  Copyright (c) 2019 wangxiaotao. All rights reserved.
//

import UIKit
import RxPlayer
import RxSwift
import RxCocoa
import RxSwiftExt

extension String: PlayerItem {
    public var playURL: URL {
        return URL(string: self)!
    }
}

struct Course: PlayerItemArrayQueue {

    typealias T = String

    var items: [T] {
        return ["http://aliuwmp3.changba.com/userdata/video/45F6BD5E445E4C029C33DC5901307461.mp4",
         "http://aliuwmp3.changba.com/userdata/video/3B1DDE764577E0529C33DC5901307461.mp4",
         "http://lzaiuw.changba.com/userdata/video/940071102.mp4",
         "http://qiniuuwmp3.changba.com/941946870.mp4"]
    }
}

let player = RxQueuePlayer<Course, String>()

class ViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!

    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var playedTimeLabel: UILabel!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var stateLabel: UILabel!
    @IBOutlet weak var plackbackStateLabel: UILabel!

    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!

    private let queue = Course()


    private let disposeBag = DisposeBag()

    private let isSeeking = BehaviorRelay(value: false)

    override func viewDidLoad() {
        super.viewDidLoad()

        playButton.rx.tap
            .bind(to: player.play)
            .disposed(by: disposeBag)

        pauseButton.rx.tap
            .bind(to: player.pause)
            .disposed(by: disposeBag)

        player.queue.onNext(queue)

        Observable.just(())
            .delay(0.1, scheduler: MainScheduler.instance)
            .subscribe(onNext: { 
                player.item.onNext(self.queue.items.first!)
            })
            .disposed(by: disposeBag)

        player.duration.map(String.init)
            .asDriver(onErrorJustReturn: "")
            .drive(durationLabel.rx.text)
            .disposed(by: disposeBag)

        player.playedTime.map(String.init)
            .asDriver(onErrorJustReturn: "")
            .drive(playedTimeLabel.rx.text)
            .disposed(by: disposeBag)

        player.playedTime
            .withLatestFrom(player.duration) { ($0, $1) }
            .map { Float($0 / $1) }
            .pausable(isSeeking.not())
            .pausable(player.isSeeking.not())
            .asDriver(onErrorJustReturn: 0.0)
            .drive(slider.rx.value)
            .disposed(by: disposeBag)

        slider.rx
            .controlEvent(.touchDown)
            .mapTo(true)
            .bind(to: isSeeking)
            .disposed(by: disposeBag)

        slider.rx
            .controlEvent([.touchUpInside, .touchUpOutside, .touchCancel])
            .mapTo(false)
            .delay(0.3, scheduler: MainScheduler.instance)
            .bind(to: isSeeking)
            .disposed(by: disposeBag)

        slider.rx
            .controlEvent([.touchUpInside, .touchUpOutside])
            .withLatestFrom( Observable.combineLatest(slider.rx.value, player.duration) )
            .map { TimeInterval($0.0) * $0.1 }
            .bind(to: player.seek)
            .disposed(by: disposeBag)

        player
            ._status
            .map { $0.rawValue }
            .bind(to: stateLabel.rx.text)
            .disposed(by: disposeBag)

        player
            .isPlaying
            .map { $0 ? "playing" : "paused" }
            .bind(to: plackbackStateLabel.rx.text)
            .disposed(by: disposeBag)

        player
            .isPlaybackLikelyToKeepUp
            .not()
            .map { $0 ? "loading" : "load done" }
            .bind(to: stopButton.rx.title())
            .disposed(by: disposeBag)

        nextButton.rx
            .tap
            .bind(to: player.next)
            .disposed(by: disposeBag)

        previousButton.rx
            .tap
            .bind(to: player.previous)
            .disposed(by: disposeBag)

        player.hasNextItem
            .debug("accept hasNextItem")
            .bind(to: nextButton.rx.isEnabled)
            .disposed(by: disposeBag)

        player.hasPreviousItem
            .debug("accept hasPreviousItem")
            .bind(to: previousButton.rx.isEnabled)
            .disposed(by: disposeBag)

        Observable.combineLatest(
            player.item,
            player.duration,
            player.playedTime,
            player.isPlaying
            ).subscribe(onNext: {
                MPNowPlayingInfoCenter.default().updatePlayingCenter(with: $0.0, duration: $0.1, progression: $0.2, rate: $0.3 ? 1 : 0)
            })
            .disposed(by: disposeBag)
    }

}

extension ViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return queue.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = queue.items[indexPath.row]
        var cell = tableView.dequeueReusableCell(withIdentifier: "cell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        }
        cell!.textLabel?.text = item.playURL.absoluteString
        player.item
            .map { $0 == item }
            .subscribe(onNext: {
                cell!.textLabel?.textColor = $0 ? .red : .gray
            })
            .disposed(by: disposeBag)
        return cell!
    }
}

extension ViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        player.item.onNext(queue.items[indexPath.row])
    }
}

import MediaPlayer

extension MPNowPlayingInfoCenter {

    func updatePlayingCenter(with item: String?, duration: TimeInterval, progression: TimeInterval, rate: Float) {
        if let item = item {
            var info: [String: Any] = [:]
            info[MPMediaItemPropertyTitle] = "title"
            info[MPMediaItemPropertyArtist] = "artist"
            //                    info[MPMediaItemPropertyAlbumTitle] = album
            //                    info[MPMediaItemPropertyArtwork] = artwork
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progression
            info[MPNowPlayingInfoPropertyPlaybackRate] = rate
            nowPlayingInfo = info
        } else {
            nowPlayingInfo = nil
        }
    }
}
