// Copyright (c) 2026 InteliWEAR LLC.
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        EventLog.append("App launched; registered for remote notifications")

        if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in
                _ = await AppModel.shared.processPushAndCleanUp(userInfo, source: "Launch notification")
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            AppModel.shared.setPushToken(from: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        EventLog.append("APNs registration failed: \(error.localizedDescription)")
        Task { @MainActor in
            AppModel.shared.failRemoteNotificationRegistration(error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let didHandle = await AppModel.shared.processPushAndCleanUp(userInfo, source: "Background push")
            completionHandler(didHandle ? .newData : .failed)
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.scheme?.lowercased() == "sidepulse",
           ["p", "pair"].contains(url.host?.lowercased() ?? "") {
            Task { @MainActor in
                AppModel.shared.receivePairingURL(url)
            }
            return true
        }
        guard let resolution = PushPayloadResolver.resolve(url: url) else {
            return false
        }
        Task { @MainActor in
            AppModel.shared.processResolvedPush(resolution, source: "Shortcut URL", isRemote: false)
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let userInfo = notification.request.content.userInfo
        let shouldPresent = await MainActor.run {
            AppModel.shared.acceptsPush(userInfo)
        }
        _ = await AppModel.shared.processPushAndCleanUp(userInfo, source: "Foreground push")
        return shouldPresent ? [.banner, .sound] : []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let _ = await AppModel.shared.processPushAndCleanUp(
            response.notification.request.content.userInfo,
            source: "Opened notification"
        )
    }
}
