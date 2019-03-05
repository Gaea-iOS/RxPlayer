//
//  Reachability+Extension.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import Reachability

extension Reachability {

    var isConnected: Bool {
        return connection != .none
    }
}
