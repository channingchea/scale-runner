import Flutter
import UIKit
import CoreAudioKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Register the BLE-MIDI pairing channel once the Flutter view controller
    // for this scene exists.
    if let window = (scene as? UIWindowScene)?.windows.first,
       let flutterVC = window.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "scale_runner/ble_midi",
        binaryMessenger: flutterVC.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "showBluetoothPairing" {
          self?.showBluetoothMidiPairing(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func showBluetoothMidiPairing(result: @escaping FlutterResult) {
    guard let root = topViewController() else {
      result(FlutterError(code: "no_vc",
                          message: "No view controller to present from", details: nil))
      return
    }
    let btvc = CABTMIDICentralViewController()
    let nav = UINavigationController(rootViewController: btvc)
    btvc.navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .done, target: self, action: #selector(dismissPairing))
    root.present(nav, animated: true) { result(nil) }
  }

  @objc private func dismissPairing() {
    topViewController()?.dismiss(animated: true)
  }

  private func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
