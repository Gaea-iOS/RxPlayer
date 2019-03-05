////
////  BackgroundTaskCreator.swift
////  RxPlayer
////
////  Created by 王小涛 on 2019/3/4.
////

class BackgroundTaskCreator {

    private let backgroundTaskCreator = UIApplication.shared

    private var taskID = UIBackgroundTaskIdentifier.invalid

    func beginBackgroundTask() {
        let newTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        if self.taskID != .invalid {
            UIApplication.shared.endBackgroundTask(self.taskID)
        }
        self.taskID = newTaskID
    }

    func endBackgroundTask() {
        if self.taskID != .invalid {
            UIApplication.shared.endBackgroundTask(self.taskID)
            self.taskID = .invalid
        }
    }
}
