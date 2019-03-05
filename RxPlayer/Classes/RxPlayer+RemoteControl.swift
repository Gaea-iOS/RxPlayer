//
//  RxPlayer+RemoteControl.swift
//  RxPlayer
//
//  Created by 王小涛 on 2019/3/5.
//

import MediaPlayer

extension RxPlayer {

    @objc public func setupRemoteControls() {

        MPRemoteCommandCenter.shared().playCommand.addTarget { [unowned self] _ in
            self.play.onNext(())
            return .success
        }

        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [unowned self] _ in
            self.pause.onNext(())
            return .success
        }
    }
}


extension RxQueuePlayer {

    public override func setupRemoteControls() {

        super.setupRemoteControls()

        MPRemoteCommandCenter.shared().nextTrackCommand.addTarget { _ in
            self.next.onNext(())
            return .success
        }

        MPRemoteCommandCenter.shared().previousTrackCommand.addTarget { _ in
            self.previous.onNext(())
            return .success
        }
    }
}
