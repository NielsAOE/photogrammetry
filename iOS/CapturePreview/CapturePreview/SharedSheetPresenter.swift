// MARK: - File: SharedSheetPresenter.swift
import SwiftUI
import UIKit

/// A lightweight, reusable presenter for UIActivityViewController from SwiftUI without keeping a custom representable in view state.
final class SharedSheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = SharedSheetPresenter()
    private var controller: UIActivityViewController?

    func present(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller = vc
        Task { @MainActor in
            guard let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let root = scene.keyWindow?.rootViewController else { return }
            root.present(vc, animated: true)
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { self.windows.first { $0.isKeyWindow } }
}
