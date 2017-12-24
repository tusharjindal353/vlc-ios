/*****************************************************************************
 * KeychainCoordinator.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2017 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors:Carola Nitz <caro # videolan.org>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

import Foundation
import LocalAuthentication

@objc(VLCKeychainCoordinator)
class KeychainCoordinator:NSObject, PAPasscodeViewControllerDelegate {

    @objc class var passcodeLockEnabled:Bool {
        return UserDefaults.standard.bool(forKey:kVLCSettingPasscodeOnKey)
    }

    private var touchIDEnabled:Bool {
        return UserDefaults.standard.bool(forKey:kVLCSettingPasscodeAllowTouchID)
    }
    private var faceIDEnabled:Bool {
        return UserDefaults.standard.bool(forKey:kVLCSettingPasscodeAllowFaceID)
    }

    static let passcodeService = "org.videolan.vlc-ios.passcode"

    var completion: (() -> ())? = nil

    private var avoidPromptingTouchOrFaceID = false

    private var passcodeLockController:PAPasscodeViewController {
        let passcodeController = PAPasscodeViewController()
        passcodeController.delegate = self
        return passcodeController
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(appInForeground), name: .UIApplicationDidBecomeActive, object: nil)
    }

    @objc class func setPasscode(passcode:String?) {
        guard let passcode = passcode else {
            try? XKKeychainGenericPasswordItem.removeItems(forService: passcodeService)
            return
        }
        let keychainItem = XKKeychainGenericPasswordItem()
        keychainItem.service = passcodeService
        keychainItem.account = passcodeService
        keychainItem.secret.stringValue = passcode
        try? keychainItem.save()
    }

    @objc func validatePasscode(completion:@escaping ()->()) {
        passcodeLockController.passcode = passcodeFromKeychain()
        self.completion = completion
        guard let rootViewController = UIApplication.shared.delegate?.window??.rootViewController else {
            return
        }
        if rootViewController.presentedViewController != nil {
            rootViewController.dismiss(animated: false, completion: nil)
        }

        let navigationController = UINavigationController(rootViewController: passcodeLockController)
        navigationController.modalPresentationStyle = .fullScreen

        rootViewController.present(navigationController, animated: true) {
            [weak self] in
            if (self?.touchIDEnabled == true || self?.faceIDEnabled == true) {
                self?.touchOrFaceIDQuery()
            }
        }
    }

    @objc private func appInForeground(notification:Notification) {
        if let navigationController = UIApplication.shared.delegate?.window??.rootViewController?.presentedViewController as? UINavigationController, navigationController.topViewController is PAPasscodeViewController, touchIDEnabled {
            touchOrFaceIDQuery()
        }
    }

    private func touchOrFaceIDQuery() {
        if (avoidPromptingTouchOrFaceID || UIApplication.shared.applicationState != .active) {
            return
        }
        let laContext = LAContext()
        if laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil){
            avoidPromptingTouchOrFaceID = true
            laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                     localizedReason: NSLocalizedString("BIOMETRIC_UNLOCK", comment: ""),
                                     reply: { [weak self ] success, _ in
                                        DispatchQueue.main.async {
                                            if success {
                                                UIApplication.shared.delegate?.window??.rootViewController?.dismiss(animated: true, completion: {
                                                    self?.completion?()
                                                    self?.completion = nil
                                                    self?.avoidPromptingTouchOrFaceID = false
                                                })
                                            } else {
                                                //user hit cancel and wants to enter the passcode
                                                self?.avoidPromptingTouchOrFaceID = true
                                            }
                                        }

            })
        }
    }

    private func passcodeFromKeychain() -> String {
        let item = try? XKKeychainGenericPasswordItem(forService: KeychainCoordinator.passcodeService, account: KeychainCoordinator.passcodeService)
        return item?.secret?.stringValue ?? ""
    }

    //MARK: PAPassCodeDelegate
    func paPasscodeViewControllerDidEnterPasscode(_ controller: PAPasscodeViewController!) {
        avoidPromptingTouchOrFaceID = false
        UIApplication.shared.delegate?.window??.rootViewController?.dismiss(animated: true, completion: {
            self.completion?()
            self.completion = nil
        })
    }

}