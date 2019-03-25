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
    associatedtype T: PlayerItem & Equatable
    func nextItem(of item: T) -> T?
    func previousItem(of item: T) -> T?
}

public protocol PlayerItemArrayQueue: PlayerItemQueue {
    var items: [T] { get }
}

extension PlayerItemArrayQueue {

    public func nextItem(of item: T) -> T? {
        let index = items.firstIndex { $0 == item }
        if let index = index, index < items.count - 1 {
            return items[index + 1]
        } else {
            return nil
        }
    }

    public func previousItem(of item: T) -> T? {
        let index = items.firstIndex { $0 == item }
        if let index = index, index > 0 {
            return items[index - 1]
        } else {
            return nil
        }
    }
}

public class RxQueuePlayer<Q: PlayerItemQueue, T>: RxPlayer<T> where Q.T == T {

    public private(set) var queue = PublishSubject<Q>()

    public let next = PublishSubject<()>()
    public let previous = PublishSubject<()>()

    public var hasNextItem: Observable<Bool> {
        return _hasNextItem.asObservable()
    }

    public var hasPreviousItem: Observable<Bool> {
        return _hasPreviousItem.asObservable()
    }

    public var didQueuePlayToEnd: Observable<()> {
        return _didQueuePlayToEnd.asObserver()
    }

    public var didQueuePlayToBegin: Observable<()> {
        return _didQueuePlayToEnd.asObserver()
    }

    private let _hasNextItem = BehaviorRelay(value: false)
    private let _hasPreviousItem = BehaviorRelay(value: false)
    private let _didQueuePlayToEnd = PublishSubject<()>()
    private let _didQueuePlayToBegin = PublishSubject<()>()

    public override init() {
        super.init()

        let nextItem = Observable.merge(
            next,
            didPlayToEndTime
            )
            .withLatestFrom(Observable.combineLatest(queue, item))
            .map { $0.0.nextItem(of: $0.1) }
            .share()

        nextItem
            .unwrap()
            .bind(to: item)
            .disposed(by: disposeBag)

        nextItem
            .filterNil()
            .mapToVoid()
            .bind(to: _didQueuePlayToEnd)
            .disposed(by: disposeBag)

        let previousItem = previous
            .withLatestFrom(Observable.combineLatest(queue, item))
            .map { $0.0.previousItem(of: $0.1) }
            .share()

        previousItem
            .unwrap()
            .bind(to: item)
            .disposed(by: disposeBag)

        previousItem
            .filterNil()
            .mapToVoid()
            .bind(to: _didQueuePlayToBegin)
            .disposed(by: disposeBag)

        Observable.combineLatest(queue, item)
            .map { $0.0.nextItem(of: $0.1) != nil }
            .bind(to: _hasNextItem)
            .disposed(by: disposeBag)

        Observable.combineLatest(queue, item)
            .map { $0.0.previousItem(of: $0.1) != nil }
            .bind(to: _hasPreviousItem)
            .disposed(by: disposeBag)
    }
}

