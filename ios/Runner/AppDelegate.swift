import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    ensureFirebaseConfigured()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Under Flutter 3.47's implicit-engine lifecycle, plugin registration can
  /// configure Firebase before didFinishLaunching runs. Calling configure() a
  /// second time raises +[FIRApp appWasConfiguredTwice:] and aborts, so every
  /// call site goes through this guard.
  private func ensureFirebaseConfigured() {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
  }

  // Forward the APNs token to Firebase Messaging explicitly rather than relying
  // on GULAppDelegateSwizzler to intercept it. The swizzler is only installed by
  // the messaging plugin's setup, which can be missed entirely (see
  // kickFirebaseMessagingSetup), leaving getAPNSToken() null and blocking FCM
  // token generation. Setting it here makes token capture deterministic.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    ensureFirebaseConfigured()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    kickFirebaseMessagingSetup(registry: engineBridge.pluginRegistry)
  }

  /// Workaround for flutter/flutter#185048 — keeps FCM working under UIScene.
  ///
  /// FLTFirebaseMessagingPlugin drives all of its setup from two callbacks:
  /// UIApplicationDidFinishLaunchingNotification and scene:willConnectToSession:.
  /// Under the UIScene lifecycle the implicit Flutter engine — and therefore
  /// plugin registration — is created during scene connection, which is *after*
  /// both of those have already fired. So the plugin registers too late to
  /// observe either one and never runs setupNotificationHandling, meaning:
  /// registerForRemoteNotifications is never called (iOS never vends an APNs
  /// token, so getAPNSToken() is null and no FCM token is issued) and the
  /// UNUserNotificationCenter delegate is never installed (foreground messages
  /// never reach Dart).
  ///
  /// firebase_messaging already handles this exact "missed the launch
  /// notification" case on macOS but has no iOS equivalent, so we replay the
  /// notification to the plugin ourselves once registration has completed. The
  /// plugin guards internally on _notificationHandlingSetup, so this is a no-op
  /// if it did manage to set itself up. Remove once #185048 is fixed upstream.
  private func kickFirebaseMessagingSetup(registry: FlutterPluginRegistry) {
    guard let plugin = registry.valuePublished(byPlugin: "FLTFirebaseMessagingPlugin")
    else { return }

    let selector = NSSelectorFromString("application_onDidFinishLaunchingNotification:")
    guard plugin.responds(to: selector) else { return }

    let launchNotification = Notification(
      name: UIApplication.didFinishLaunchingNotification, object: nil)
    plugin.perform(selector, with: launchNotification as NSNotification)
  }
}
