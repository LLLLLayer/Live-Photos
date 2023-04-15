//
//  Toast.swift
//  LivePhotos
//
//  Created by yangjie.layer on 2023/4/7.
//

import UIKit

enum Toast {
    static func show(_ text: String) {
        Task { @MainActor in
            guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
                  let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootViewController = keyWindow.rootViewController else {
                return
            }
            let topViewController: UIViewController?
            if let presentedViewController = rootViewController.presentedViewController {
                topViewController = presentedViewController
            } else if let navigationController = rootViewController as? UINavigationController {
                topViewController = navigationController.topViewController
            } else if let tabBarController = rootViewController as? UITabBarController {
                topViewController = tabBarController.selectedViewController
            } else {
                topViewController = rootViewController
            }
            guard let view = topViewController?.view else {
                return
            }
            let toastLabel = UILabel()
            toastLabel.text = text
            toastLabel.textAlignment = .center
            toastLabel.backgroundColor = .label
            toastLabel.textColor = .systemBackground
            toastLabel.layer.cornerRadius = 4.0
            toastLabel.layer.masksToBounds = true
            toastLabel.sizeToFit()
            view.addSubview(toastLabel)
            toastLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                toastLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                toastLabel.widthAnchor.constraint(equalToConstant: toastLabel.frame.width + 10),
                toastLabel.heightAnchor.constraint(equalToConstant: toastLabel.frame.height + 10)
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                toastLabel.removeFromSuperview()
            }
        }
    }
}
