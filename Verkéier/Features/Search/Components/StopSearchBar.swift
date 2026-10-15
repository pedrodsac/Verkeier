import SwiftUI
import UIKit

struct StopSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isActive: Bool
    @Binding var focusRequested: Bool
    var placeholder = "Search stops"
    var accessibilityIdentifier = "stop-search"
    var accessibilityLabel = "Stop search"
    let onActivate: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.backgroundImage = UIImage()
        searchBar.backgroundColor = .clear
        searchBar.barTintColor = .clear
        searchBar.placeholder = placeholder
        searchBar.accessibilityIdentifier = accessibilityIdentifier
        searchBar.searchTextField.accessibilityLabel = accessibilityLabel
        return searchBar
    }

    func updateUIView(_ uiView: UISearchBar, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }

        if uiView.showsCancelButton != isActive {
            uiView.setShowsCancelButton(isActive, animated: true)
        }

        if focusRequested, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard self.focusRequested else { return }
                guard !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isActive, uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard !self.isActive else { return }
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: StopSearchBar

        init(_ parent: StopSearchBar) {
            self.parent = parent
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            parent.isActive = true
            parent.onActivate()
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.onCancel()
        }
    }
}
