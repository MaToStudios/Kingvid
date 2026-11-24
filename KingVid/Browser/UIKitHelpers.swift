import UIKit

extension UIApplication {
    var topMostViewController: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// Native replacements for the JavaScript alert / confirm / prompt dialogs.
@MainActor
enum Alerts {
    static func alert(title: String, message: String, completion: @escaping () -> Void) {
        guard let top = UIApplication.shared.topMostViewController else { completion(); return }
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.view.tintColor = UIColor(Theme.gold)
        controller.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion() })
        top.present(controller, animated: true)
    }

    static func confirm(title: String, message: String, completion: @escaping (Bool) -> Void) {
        guard let top = UIApplication.shared.topMostViewController else { completion(false); return }
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.view.tintColor = UIColor(Theme.gold)
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        controller.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        top.present(controller, animated: true)
    }

    static func prompt(title: String, message: String, defaultText: String?, completion: @escaping (String?) -> Void) {
        guard let top = UIApplication.shared.topMostViewController else { completion(nil); return }
        let controller = UIAlertController(title: title, message: message, preferredStyle: .alert)
        controller.view.tintColor = UIColor(Theme.gold)
        controller.addTextField { $0.text = defaultText }
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        controller.addAction(UIAlertAction(title: "OK", style: .default) { [weak controller] _ in
            completion(controller?.textFields?.first?.text)
        })
        top.present(controller, animated: true)
    }
}
