import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var eventSink: FlutterEventSink?
  private let PHOTO_CHANGES_CHANNEL = "com.example.filtored/photo_changes"
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let controller = window?.rootViewController as! FlutterViewController
    let eventChannel = FlutterEventChannel(
      name: PHOTO_CHANGES_CHANNEL,
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(PhotoChangeHandler())
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

class PhotoChangeHandler: NSObject, FlutterStreamHandler, PHPhotoLibraryChangeObserver {
  private var eventSink: FlutterEventSink?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    PHPhotoLibrary.shared().register(self)
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    PHPhotoLibrary.shared().unregisterChangeObserver(self)
    self.eventSink = nil
    return nil
  }
  
  func photoLibraryDidChange(_ changeInstance: PHChange) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(["type": "change"])
    }
  }
}
