import AVFoundation
import Flutter
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Show the daily reminder banner even while the app is open.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TeitenMediaPlugin") {
      TeitenMediaPlugin.register(with: registrar)
    }
  }
}

/// On-device video work for the "same time, every day" sequence:
/// - export: concatenates the day clips, burns the date of each day into the
///   frames and writes one H.264 .mp4 (AVFoundation only, nothing leaves the device)
/// - saveToPhotos: adds a video to the Photos library (add-only permission)
/// - frame: writes a JPEG of the first frame of a clip (used as the framing guide)
final class TeitenMediaPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "teiten/media", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(TeitenMediaPlugin(), channel: channel)
  }

  private let queue = DispatchQueue(label: "teiten.media", qos: .userInitiated)

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "export":
      queue.async { Self.export(args) { r in DispatchQueue.main.async { result(r) } } }
    case "saveToPhotos":
      guard let path = args["path"] as? String else { return result(FlutterError(code: "args", message: "path", details: nil)) }
      Self.saveToPhotos(URL(fileURLWithPath: path)) { ok in DispatchQueue.main.async { result(ok) } }
    case "frame":
      guard let path = args["path"] as? String, let out = args["out"] as? String else { return result(false) }
      queue.async {
        let ok = Self.writeFrame(URL(fileURLWithPath: path), to: URL(fileURLWithPath: out))
        DispatchQueue.main.async { result(ok) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: frame

  static func writeFrame(_ video: URL, to out: URL) -> Bool {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video))
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
    guard let cg = try? gen.copyCGImage(at: CMTime(value: 1, timescale: 10), actualTime: nil),
          let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { return false }
    return (try? data.write(to: out)) != nil
  }

  // MARK: photos

  static func saveToPhotos(_ url: URL, done: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else { return done(false) }
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
      }) { ok, _ in done(ok) }
    }
  }

  // MARK: export

  static let renderSize = CGSize(width: 1080, height: 1920)

  static func export(_ args: [String: Any], done: @escaping (Any?) -> Void) {
    guard let items = args["clips"] as? [[String: Any]], !items.isEmpty,
          let outPath = args["out"] as? String else {
      return done(FlutterError(code: "args", message: "clips/out", details: nil))
    }
    let per = (args["secondsPerClip"] as? Double) ?? 1.0
    let title = (args["title"] as? String) ?? ""
    let out = URL(fileURLWithPath: outPath)
    try? FileManager.default.removeItem(at: out)

    let comp = AVMutableComposition()
    guard let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
      return done(FlutterError(code: "compose", message: "no track", details: nil))
    }
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    var cursor = CMTime.zero
    var labels: [(String, CMTimeRange)] = []
    for item in items {
      guard let path = item["path"] as? String else { continue }
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let src = asset.tracks(withMediaType: .video).first else { continue }
      let want = CMTime(seconds: per, preferredTimescale: 600)
      let dur = CMTimeMinimum(want, asset.duration)
      guard dur.seconds > 0.05 else { continue }
      do {
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: src, at: cursor)
      } catch { continue }
      layer.setTransform(fill(src), at: cursor)
      labels.append(((item["label"] as? String) ?? "", CMTimeRange(start: cursor, duration: dur)))
      cursor = cursor + dur
    }
    guard cursor.seconds > 0 else {
      return done(FlutterError(code: "compose", message: "no readable clips", details: nil))
    }

    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
    instruction.layerInstructions = [layer]
    let video = AVMutableVideoComposition()
    video.renderSize = renderSize
    video.frameDuration = CMTime(value: 1, timescale: 30)
    video.instructions = [instruction]
    video.animationTool = overlay(title: title, labels: labels, total: cursor)

    guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
      return done(FlutterError(code: "export", message: "no session", details: nil))
    }
    session.outputURL = out
    session.outputFileType = .mp4
    session.videoComposition = video
    session.shouldOptimizeForNetworkUse = true
    session.exportAsynchronously {
      if session.status == .completed {
        done(out.path)
      } else {
        done(FlutterError(code: "export", message: session.error?.localizedDescription ?? "failed", details: nil))
      }
    }
  }

  /// Orients a source track upright and scales it to fill the portrait frame.
  static func fill(_ src: AVAssetTrack) -> CGAffineTransform {
    let t = src.preferredTransform
    let r = CGRect(origin: .zero, size: src.naturalSize).applying(t)
    let size = CGSize(width: abs(r.width), height: abs(r.height))
    let scale = max(renderSize.width / size.width, renderSize.height / size.height)
    let dx = (renderSize.width - size.width * scale) / 2
    let dy = (renderSize.height - size.height * scale) / 2
    return t
      .concatenating(CGAffineTransform(translationX: -r.minX, y: -r.minY))
      .concatenating(CGAffineTransform(scaleX: scale, y: scale))
      .concatenating(CGAffineTransform(translationX: dx, y: dy))
  }

  /// Text burned into the video: the spot (time + name) all the time,
  /// and the date of whichever day is on screen.
  static func overlay(title: String, labels: [(String, CMTimeRange)], total: CMTime) -> AVVideoCompositionCoreAnimationTool {
    let frame = CGRect(origin: .zero, size: renderSize)
    let parent = CALayer()
    parent.frame = frame
    let videoLayer = CALayer()
    videoLayer.frame = frame
    parent.addSublayer(videoLayer)

    // Soft shade at the bottom so the text stays readable on bright frames.
    let shade = CAGradientLayer()
    shade.frame = CGRect(x: 0, y: 0, width: renderSize.width, height: 520)
    shade.colors = [UIColor.black.withAlphaComponent(0.55).cgColor, UIColor.clear.cgColor]
    shade.startPoint = CGPoint(x: 0.5, y: 0)
    shade.endPoint = CGPoint(x: 0.5, y: 1)
    parent.addSublayer(shade)

    // Core Animation's origin is bottom-left here.
    if let img = textImage(title, size: 44, weight: .semibold) {
      let l = CALayer()
      l.contents = img
      l.frame = CGRect(x: 64, y: 250, width: CGFloat(img.width), height: CGFloat(img.height))
      parent.addSublayer(l)
    }
    let totalSec = total.seconds
    for (text, range) in labels {
      guard let img = textImage(text, size: 76, weight: .heavy) else { continue }
      let l = CALayer()
      l.contents = img
      l.frame = CGRect(x: 60, y: 130, width: CGFloat(img.width), height: CGFloat(img.height))
      l.opacity = 0
      let a = CAKeyframeAnimation(keyPath: "opacity")
      a.calcMode = .discrete
      a.values = [0, 1, 0]
      a.keyTimes = [0, NSNumber(value: range.start.seconds / totalSec), NSNumber(value: range.end.seconds / totalSec), 1]
      a.duration = totalSec
      a.beginTime = AVCoreAnimationBeginTimeAtZero
      a.isRemovedOnCompletion = false
      a.fillMode = .forwards
      l.add(a, forKey: "show")
      parent.addSublayer(l)
    }
    return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
  }

  /// Renders text with a soft shadow into an image (reliable for Japanese text).
  static func textImage(_ text: String, size: CGFloat, weight: UIFont.Weight) -> CGImage? {
    guard !text.isEmpty else { return nil }
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
    shadow.shadowOffset = .zero
    let attrs: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: size, weight: weight),
      .foregroundColor: UIColor.white,
      .shadow: shadow,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let b = s.boundingRect(with: CGSize(width: renderSize.width - 120, height: 400), options: [.usesLineFragmentOrigin], context: nil)
    let sz = CGSize(width: ceil(b.width) + 24, height: ceil(b.height) + 24)
    let fmt = UIGraphicsImageRendererFormat()
    fmt.scale = 1
    fmt.opaque = false
    let img = UIGraphicsImageRenderer(size: sz, format: fmt).image { _ in s.draw(at: CGPoint(x: 12, y: 12)) }
    return img.cgImage
  }
}
