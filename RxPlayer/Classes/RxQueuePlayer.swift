//
//  RxQueuePlayer.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/2/22.
//

import RxSwift
import RxCocoa
import RxSwiftExt
import AVFoundation

public protocol PlayerItemQueue {
    var startItem: PlayerItem? { get }
    func nextItem(of item: PlayerItem?) -> PlayerItem?
    func previousItem(of item: PlayerItem?) -> PlayerItem?
}

public protocol PlayerItemArrayQueue: PlayerItemQueue {
    var items: [PlayerItem] { get }
}

extension PlayerItemArrayQueue {

    public var startItem: PlayerItem? {
        return items.first
    }

    public func nextItem(of item: PlayerItem?) -> PlayerItem? {
        guard let item = item else {
            return nil
        }
        let index = items.firstIndex { $0.playURL == item.playURL }
        if let index = index, index < items.count - 1 {
            return items[index + 1]
        } else {
            return nil
        }
    }

    public func previousItem(of item: PlayerItem?) -> PlayerItem? {
        guard let item = item else {
            return nil
        }
        let index = items.firstIndex { $0.playURL == item.playURL }
        if let index = index, index > 0 {
            return items[index - 1]
        } else {
            return nil
        }
    }
}

public class RxQueuePlayer: RxPlayer {

    public private(set) var queue = PublishSubject<PlayerItemQueue>()

    private let disposeBag = DisposeBag()

    public private(set) var next = PublishSubject<()>()
    public private(set) var previous = PublishSubject<()>()

    public var hasNextItem: Observable<Bool> {
        return _hasNextItem.asObservable()
    }

    public var hasPreviousItem: Observable<Bool> {
        return _hasPreviousItem.asObservable()
    }

    public private(set) var _hasNextItem = BehaviorRelay(value: false)
    public private(set) var _hasPreviousItem = BehaviorRelay(value: false)



    public override init() {
        super.init()
        queue
            .map { $0.startItem }
            .bind(to: item)
            .disposed(by: disposeBag)

        didPlayToEndTime
            .withLatestFrom(item.unwrap())
            .withLatestFrom(queue) { ($0, $1) }
            .map { $1.nextItem(of: $0) }
            .bind(to: item)
            .disposed(by: disposeBag)

        Observable.combineLatest(queue, item)
            .map { $0.0.nextItem(of: $0.1) != nil }
            .bind(to: _hasNextItem)
            .disposed(by: disposeBag)

        Observable.combineLatest(queue, item)
            .map { $0.0.previousItem(of: $0.1) != nil }
            .bind(to: _hasPreviousItem)
            .disposed(by: disposeBag)

        next
            .withLatestFrom( Observable.combineLatest(queue, item) )
            .map { $0.0.nextItem(of: $0.1) }
            .unwrap()
            .bind(to: item)
            .disposed(by: disposeBag)

        previous
            .withLatestFrom( Observable.combineLatest(queue, item) )
            .map { $0.0.previousItem(of: $0.1) }
            .unwrap()
            .bind(to: item)
            .disposed(by: disposeBag)
    }
}

