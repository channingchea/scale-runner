import Cocoa
import CoreAudioKit
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Held for the lifetime of the window: CABTLEMIDIWindowController owns the
  /// pairing panel, and a local would be deallocated the moment we return —
  /// taking the panel with it.
  private var blePairingController: CABTLEMIDIWindowController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerBleMidiChannel(flutterViewController)

    super.awakeFromNib()

    // The xib sets the title from the product name; make it explicit, and stop
    // the window being dragged down to a size the practice screens can't use.
    self.title = "Scale Runner"
    self.minSize = NSSize(width: 900, height: 640)
    if windowFrame.width < 1100 || windowFrame.height < 760 {
      self.setContentSize(NSSize(width: 1100, height: 760))
      self.center()
    }
  }

  /// macOS half of the BLE-MIDI pairing bridge. Mirrors the iOS side in
  /// `ios/Runner/SceneDelegate.swift` — same channel name, same method — but
  /// CABTMIDICentralViewController is iOS-only, so macOS uses CoreAudioKit's
  /// CABTLEMIDIWindowController (macOS 10.11+), which does the same job in a
  /// panel of its own.
  private func registerBleMidiChannel(_ flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "scale_runner/ble_midi",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "showBluetoothPairing" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.showBluetoothMidiPairing(result: result)
    }
  }

  private func showBluetoothMidiPairing(result: @escaping FlutterResult) {
    let controller = blePairingController ?? CABTLEMIDIWindowController()
    blePairingController = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    result(nil)
  }
}
