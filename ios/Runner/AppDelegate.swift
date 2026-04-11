import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure the shared AVAudioSession up front so MP3 playback in TTS
    // mode works regardless of the hardware ring/silent switch. iOS defaults
    // the category to `soloAmbient`, which is silenced by the switch, and
    // neither flutter_sound's player path nor speech_to_text's stop path
    // will set a playback-capable category for us — so TTS audio ends up
    // silent in TestFlight. `.playAndRecord` + `.defaultToSpeaker` matches
    // what speech_to_text sets while listening, so category transitions
    // in/out of STT become no-ops and playback always routes to the speaker.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      NSLog("VieSpeak: AVAudioSession configuration failed: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
