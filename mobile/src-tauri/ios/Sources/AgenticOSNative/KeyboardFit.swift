import UIKit
import WebKit

/// Keep the page still when a field opens the keyboard (#3283).
///
/// WKWebView answers the keyboard on its own: it insets its scroll view and pans
/// the page to reveal the focused field. The console's `useOnScreenKeyboard`
/// already fits the shell to the visual viewport and scrolls the window back to
/// 0, so every tap on the sign-in fields or the composer slid the whole console
/// up and back down.
///
/// Here the web view stops observing the keyboard and is made shorter instead,
/// ending at the keyboard's top - the "native" resize of Capacitor's and Ionic's
/// keyboard plugins. The visual viewport shrinks with the frame, the shell
/// follows it as it does in a browser, and the page never pans.
final class KeyboardFit: NSObject {
  private static var current: KeyboardFit?

  private weak var webview: WKWebView?
  /// The web view's frame without a keyboard; nil while it is not shortened.
  private var resting: CGRect?

  /// Once per web view, from a plugin's `load(webview:)`.
  static func install(on webview: WKWebView) {
    if current?.webview === webview { return }
    current = KeyboardFit(webview)
  }

  private init(_ webview: WKWebView) {
    self.webview = webview
    super.init()
    Self.detachWebKit(from: webview)
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    center.addObserver(
      self, selector: #selector(keyboardWillHide(_:)),
      name: UIResponder.keyboardWillHideNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private static let keyboardNotifications: [Notification.Name] = [
    UIResponder.keyboardWillShowNotification, UIResponder.keyboardDidShowNotification,
    UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification,
    UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
  ]

  /// WKWebView observes these itself, as the observer, to inset and pan the page.
  private static func detachWebKit(from webview: WKWebView) {
    for name in keyboardNotifications {
      NotificationCenter.default.removeObserver(webview, name: name, object: nil)
    }
  }

  @objc private func keyboardWillChangeFrame(_ note: Notification) {
    guard let webview, let host = webview.superview,
      let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    else { return }
    // In case WebKit observed again, for instance after moving to a new window.
    Self.detachWebKit(from: webview)
    let base = resting ?? webview.frame
    // The keyboard's frame is in screen coordinates.
    let keyboard: CGRect
    if let screen = host.window?.screen {
      keyboard = screen.coordinateSpace.convert(end, to: host)
    } else {
      keyboard = host.convert(end, from: nil)
    }
    let overlap = base.maxY - keyboard.minY
    guard keyboard.height > 0, overlap > 0 else {
      restore()
      return
    }
    resting = base
    var frame = base
    frame.size.height = max(0, base.height - overlap)
    if webview.frame != frame {
      webview.frame = frame
      revealFocusedField(in: webview)
    }
  }

  @objc private func keyboardWillHide(_ note: Notification) {
    restore()
  }

  private func restore() {
    guard let webview, let base = resting else { return }
    resting = nil
    if webview.frame != base { webview.frame = base }
  }

  /// WebKit no longer reveals the field, so a field the shorter frame left out of
  /// sight - low in a long form - is scrolled into view by the page; `nearest`
  /// leaves one already in sight where it is.
  private func revealFocusedField(in webview: WKWebView) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak webview] in
      webview?.evaluateJavaScript(
        "(function(){var e=document.activeElement;if(e&&e!==document.body&&e.scrollIntoView){e.scrollIntoView({block:'nearest',inline:'nearest'})}})()",
        completionHandler: nil)
    }
  }
}
