import Flutter
import UIKit

/// Native Liquid Glass (`UIGlassEffect`) for Flutter, as a platform view.
///
/// Flutter paints its own pixels, so UIKit's glass cannot be applied to a
/// widget directly. Instead Dart's `LiquidGlass` places a
/// `com.plezy/liquid_glass` platform view behind its child: the glass samples
/// whatever UIKit composites beneath it — Flutter's own surface, or the mpv
/// video layer that sits behind the transparent Flutter view while playing —
/// and Flutter draws the icons and labels on top.
///
/// The view never takes touches; the Flutter child above it does.
///
/// `UIGlassEffect` exists only in the iOS 26 SDK and later and `#available`
/// does not hide it from older compilers, so it is gated at compile time on
/// Swift 6.2 (Xcode 26). An older toolchain builds a plugin that reports the
/// glass unsupported, and Dart keeps its regular painted look.
final class LiquidGlassPlugin: NSObject, FlutterPlugin {
  /// Name of both the method channel and the platform view type; must match
  /// `_liquidGlassId` in `lib/widgets/liquid_glass.dart`.
  static let identifier = "com.plezy/liquid_glass"

  private let factory: LiquidGlassViewFactory

  private init(factory: LiquidGlassViewFactory) {
    self.factory = factory
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let factory = LiquidGlassViewFactory()
    let instance = LiquidGlassPlugin(factory: factory)
    let channel = FlutterMethodChannel(name: identifier, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(factory, withId: identifier)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(LiquidGlassView.isSupported)
    case "update":
      // Restyles a live view in place; recreating a platform view costs a
      // frame of compositing setup and visibly re-materializes the glass.
      guard let args = call.arguments as? [String: Any], let id = (args["id"] as? NSNumber)?.int64Value else {
        result(FlutterError(code: "INVALID_ARGS", message: "update requires an id", details: nil))
        return
      }
      factory.view(for: id)?.apply(LiquidGlassConfig(args))
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The look Dart asks for. Unknown or missing keys fall back to a regular,
/// untinted rectangle that follows the system appearance.
struct LiquidGlassConfig: Equatable {
  enum Shape: Equatable {
    case capsule
    case rect(cornerRadius: CGFloat)
  }

  enum Style: Equatable {
    case regular
    case clear
  }

  var shape: Shape = .rect(cornerRadius: 0)
  var style: Style = .regular
  var tint: UIColor?
  var interfaceStyle: UIUserInterfaceStyle = .unspecified
  var visible = true

  init(_ args: [String: Any]?) {
    guard let args else { return }
    visible = (args["visible"] as? Bool) ?? true
    if args["shape"] as? String == "capsule" {
      shape = .capsule
    } else {
      let radius = (args["cornerRadius"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 0
      shape = .rect(cornerRadius: max(0, radius.isFinite ? radius : 0))
    }
    style = args["style"] as? String == "clear" ? .clear : .regular
    if let argb = (args["tint"] as? NSNumber)?.uint32Value {
      tint = UIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
      )
    }
    switch args["brightness"] as? String {
    case "dark": interfaceStyle = .dark
    case "light": interfaceStyle = .light
    default: interfaceStyle = .unspecified
    }
  }
}

final class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  /// Live views by platform view id, for `update`. Weak, so a view Flutter
  /// disposes drops out on its own.
  private let views = NSMapTable<NSNumber, LiquidGlassView>.strongToWeakObjects()

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let view = LiquidGlassView(frame: frame, config: LiquidGlassConfig(args as? [String: Any]))
    views.setObject(view, forKey: NSNumber(value: viewId))
    return view
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func view(for id: Int64) -> LiquidGlassView? {
    views.object(forKey: NSNumber(value: id))
  }
}

final class LiquidGlassView: NSObject, FlutterPlatformView {
  /// Whether this build and OS render real Liquid Glass. Reduce Transparency
  /// and Increase Contrast need no handling here: the system glass already
  /// turns frosted and higher contrast for them.
  static var isSupported: Bool {
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) { return true }
    #endif
    return false
  }

  private let container: UIView
  private let effectView: UIVisualEffectView
  private var config: LiquidGlassConfig?

  init(frame: CGRect, config: LiquidGlassConfig) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.isUserInteractionEnabled = false
    effectView = UIVisualEffectView(effect: nil)
    effectView.frame = container.bounds
    effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    effectView.isUserInteractionEnabled = false
    container.addSubview(effectView)
    super.init()
    apply(config)
  }

  func view() -> UIView { container }

  /// Restyles the view. Dart only creates it where `isSupported` is true, so
  /// on older toolchains or OS versions this leaves the effect empty.
  func apply(_ newConfig: LiquidGlassConfig) {
    guard newConfig != config else { return }
    #if compiler(>=6.2)
      let previous = config
    #endif
    config = newConfig
    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        let effect: UIVisualEffect? = newConfig.visible ? Self.glassEffect(for: newConfig) : nil
        UIView.performWithoutAnimation {
          container.overrideUserInterfaceStyle = newConfig.interfaceStyle
          switch newConfig.shape {
          case .capsule:
            effectView.cornerConfiguration = .capsule()
          case .rect(let cornerRadius):
            effectView.cornerConfiguration = .corners(radius: .fixed(cornerRadius))
          }
        }
        // Only a visibility change animates: setting `effect` inside an
        // animation block makes UIKit materialize or dissolve the glass, which
        // stands in for an opacity fade (alpha below 1 breaks the effect).
        if let previous, previous.visible != newConfig.visible {
          UIView.animate(withDuration: 0.25) { self.effectView.effect = effect }
        } else {
          UIView.performWithoutAnimation { effectView.effect = effect }
        }
      }
    #endif
  }

  #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func glassEffect(for config: LiquidGlassConfig) -> UIGlassEffect {
      let glass = UIGlassEffect(style: config.style == .clear ? .clear : .regular)
      glass.tintColor = config.tint
      // Touches land on the Flutter child, never on this view, so the
      // interactive press response could not fire anyway.
      glass.isInteractive = false
      return glass
    }
  #endif
}
