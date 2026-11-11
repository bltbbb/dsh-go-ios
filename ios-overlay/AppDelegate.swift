import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register an iOS fallback for every Android-only MethodChannel/EventChannel.
    // Without this, calls into the local-engine bridge throw
    // MissingPluginException and take the app down on unsupported screens.
    if let registrar = self.registrar(forPlugin: "IosChannelStubs") {
      IosChannelStubs.register(with: registrar)
    } else {
      NSLog("[dsh-ios] WARNING: could not obtain a FlutterPluginRegistrar")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
