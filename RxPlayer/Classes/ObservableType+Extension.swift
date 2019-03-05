//
//  ObservableType+Extension.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import RxSwift

extension ObservableType {

    func filterNil<T>() -> Observable<T?> where E == T? {
        return filter { $0 == nil }
    }

    func mapToVoid() -> Observable<()> {
        return mapTo(())
    }
}

extension ObservableType where E == Bool {

    func filterTrue() -> Observable<Bool> {
        return filter { $0 }
    }

    func filterFalse() -> Observable<Bool> {
        return filter { !$0 }
    }
}
