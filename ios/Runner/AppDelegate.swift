import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pencilInteractionHandler: PencilInteractionHandler?

  /// Registers all pubspec-referenced Flutter plugins in the given registry
  static func registerPlugins(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      // The following code will be called upon WorkmanagerPlugin's registration.
      AppDelegate.registerPlugins(with: registry)
    }

    // At least 12 hours between background fetches
    UIApplication.shared.setMinimumBackgroundFetchInterval(TimeInterval(12 * 60 * 60))

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    AppDelegate.registerPlugins(with: engineBridge.pluginRegistry)
    pencilInteractionHandler = PencilInteractionHandler(
      messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Forwards Apple Pencil double taps and squeezes to Dart.
///
/// Dart calls `attach` once it wants to receive taps,
/// and is then sent `doubleTap` with either `ignore` or `toggle`,
/// depending on the user's double-tap setting in iPadOS.
class PencilInteractionHandler: NSObject, UIPencilInteractionDelegate {
  private let channel: FlutterMethodChannel
  private let interaction = UIPencilInteraction()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "saber/pencil_interaction", binaryMessenger: messenger)
    super.init()
    interaction.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "attach" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.attach()
      result(nil)
    }
  }

  private func attach() {
    guard interaction.view == nil else { return }
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    (window?.rootViewController?.view ?? window)?.addInteraction(interaction)
  }

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap
  ) {
    sendDoubleTap()
  }

  func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    sendDoubleTap()
  }

  /// A squeeze (Apple Pencil Pro) does the same as a double tap,
  /// once it is released.
  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard squeeze.phase == .ended else { return }
    let ignore = UIPencilInteraction.preferredSqueezeAction == .ignore
    channel.invokeMethod("doubleTap", arguments: ignore ? "ignore" : "toggle")
  }

  private func sendDoubleTap() {
    let ignore = UIPencilInteraction.preferredTapAction == .ignore
    channel.invokeMethod("doubleTap", arguments: ignore ? "ignore" : "toggle")
  }
}
