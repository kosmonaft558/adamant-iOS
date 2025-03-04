//
//  NotificationSoundsViewController.swift
//  Adamant
//
//  Created by Stanislav Jelezoglo on 31.08.2022.
//  Copyright © 2022 Adamant. All rights reserved.
//

import UIKit
import Eureka
import AudioToolbox
import AVFoundation

class NotificationSoundsViewController: FormViewController {
    
    // MARK: Sections & Rows
    enum Sections {
        case alerts
        
        var tag: String {
            switch self {
            case .alerts: return "al"
            }
        }
        
        var localized: String {
            switch self {
            case .alerts: return NSLocalizedString("Notifications.Alert.Tones", comment: "Notifications: Select Alert Tones")
            }
        }
    }
    
    var notificationsService: NotificationsService!
    private var selectSound:NotificationSound = .inputDefault
    private var section = SelectableSection<ListCheckRow<NotificationSound>>()
    var audioPlayer: AVAudioPlayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString("Notifications.Sounds.Name", comment: "Notifications: Select Sounds")
        
        selectSound = notificationsService.notificationsSound
        
        section = SelectableSection<ListCheckRow<NotificationSound>>(Sections.alerts.localized, selectionType: .singleSelection(enableDeselection: false))

        let sounds: [NotificationSound] = [.none, .noteDefault, .inputDefault, .proud, .relax, .success]
        for sound in sounds {
            section <<< ListCheckRow<NotificationSound> { listRow in
                listRow.title = sound.localized
                listRow.selectableValue = sound
                if sound == selectSound {
                    listRow.value = sound
                } else {
                    listRow.value = nil
                }
            }
        }
        
        section.onSelectSelectableRow = { [weak self] _, row in
            guard let value = row.selectableValue else { return }
            self?.playSound(value)
        }
        
        form.append(section)
        
        addBtns()
    }
    
    private func addBtns() {
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Notifications.Alert.Save", comment: "Notifications: Select Alert Save"),
            style: .done,
            target: self,
            action: #selector(save)
        )
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Notifications.Alert.Cancel", comment: "Notifications: Alerts Cancel"),
            style: .done,
            target: self,
            action: #selector(close)
        )
    }
    
    @objc private func save() {
        guard let value = section.selectedRow()?.selectableValue else { return }
        setNotificationSound(value)
        close()
    }
    
    @objc private func close() {
        self.dismiss(animated: true)
    }
    
    private func setNotificationSound(_ sound: NotificationSound) {
        notificationsService.setNotificationSound(sound)
    }
    
    private func playSound(_ sound: NotificationSound) {
        switch sound {
        case .none:
            break
        default:
            playSound(by: sound.fileName)
        }
    }
        
    private func playSound(by fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName.replacingOccurrences(of: ".mp3", with: ""), withExtension: "mp3") else {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            self.audioPlayer = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.mp3.rawValue)
            audioPlayer.volume = 1.0
            audioPlayer.play()
        } catch let error as NSError {
            print("error: \(error.localizedDescription)")
        }
    }
}
