//
//  ObservableType+Extension.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import RxSwift

extension ObservableType {

    public func filterNil<T>() -> Observable<T?> where E == T? {
        return filter { $0 == nil }
    }

    public func mapToVoid() -> Observable<()> {
        return mapTo(())
    }
}

extension ObservableType where E == Bool {

    public func filterTrue() -> Observable<Bool> {
        return filter { $0 }
    }

    public func filterFalse() -> Observable<Bool> {
        return filter { !$0 }
    }
}
