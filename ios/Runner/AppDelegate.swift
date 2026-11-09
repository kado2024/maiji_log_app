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
    var cursor = CMTime.zero
    var segments: [Segment] = []
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
      segments.append(Segment(
        range: CMTimeRange(start: cursor, duration: dur),
        orientation: orientation(of: src.preferredTransform),
        label: textImage((item["label"] as? String) ?? "", size: 76, weight: .heavy).map { CIImage(cgImage: $0) }))
      cursor = cursor + dur
    }
    guard cursor.seconds > 0, !segments.isEmpty else {
      return done(FlutterError(code: "compose", message: "no readable clips", details: nil))
    }

    // Per-frame Core Image composition: orient + fill the frame, then the
    // date of the day on screen and the spot title. (Core Image instead of
    // AVVideoCompositionCoreAnimationTool, which is unreliable on Simulator.)
    let rect = CGRect(origin: .zero, size: renderSize)
    let shade = CIFilter(name: "CILinearGradient", parameters: [
      "inputPoint0": CIVector(x: 0, y: 0),
      "inputPoint1": CIVector(x: 0, y: 560),
      "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.55),
      "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
    ])?.outputImage?.cropped(to: rect)
    let titleImage = textImage(title, size: 44, weight: .semibold).map { CIImage(cgImage: $0) }
    let black = CIImage(color: .black).cropped(to: rect)

    let video = AVMutableVideoComposition(asset: comp) { req in
      let t = req.compositionTime
      let seg = segments.first { $0.range.containsTime(t) } ?? segments.last!
      var img = fill(req.sourceImage.oriented(seg.orientation)).composited(over: black)
      if let shade = shade { img = shade.composited(over: img) }
      if let title = titleImage { img = title.transformed(by: CGAffineTransform(translationX: 64, y: 250)).composited(over: img) }
      if let label = seg.label { img = label.transformed(by: CGAffineTransform(translationX: 60, y: 130)).composited(over: img) }
      req.finish(with: img.cropped(to: rect), context: nil)
    }
    video.renderSize = renderSize
    video.frameDuration = CMTime(value: 1, timescale: 30)

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

  struct Segment {
    let range: CMTimeRange
    let orientation: CGImagePropertyOrientation
    let label: CIImage?
  }

  /// How to turn a track's stored pixels upright (from its preferredTransform).
  static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
    switch (t.a, t.b, t.c, t.d) {
    case (0, 1, -1, 0): return .right
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, -1): return .down
    case (-1, 0, 0, 1): return .upMirrored
    case (0, 1, 1, 0): return .leftMirrored
    case (0, -1, -1, 0): return .rightMirrored
    default: return .up
    }
  }

  /// Scales an upright frame to fill the portrait render size (center crop).
  static func fill(_ img: CIImage) -> CIImage {
    let e = img.extent
    let scale = max(renderSize.width / e.width, renderSize.height / e.height)
    let s = img.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let dx = (renderSize.width - e.width * scale) / 2
    let dy = (renderSize.height - e.height * scale) / 2
    return s.transformed(by: CGAffineTransform(translationX: dx, y: dy))
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
