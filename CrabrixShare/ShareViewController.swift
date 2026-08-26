import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let doneButton = UIButton(type: .system)
    private var didBeginImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didBeginImport else { return }
        didBeginImport = true
        findSharedGitHubURL()
    }

    private func configureView() {
        view.backgroundColor = UIColor(red: 0.045, green: 0.063, blue: 0.083, alpha: 1)
        statusLabel.text = "Saving to Crabrix…"
        statusLabel.textColor = .white
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        detailLabel.text = "Crabrix will import the repository when you open the app."
        detailLabel.textColor = .secondaryLabel
        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        spinner.color = UIColor(red: 1.0, green: 0.39, blue: 0.27, alpha: 1)
        spinner.startAnimating()
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func findSharedGitHubURL() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                let rawValue = Self.stringValue(from: item)
                let errorMessage = error?.localizedDescription
                Task { @MainActor [weak self, rawValue, errorMessage] in
                    self?.handleLoadedValue(rawValue, errorMessage: errorMessage)
                }
            }
            return
        }
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
                let rawValue = Self.stringValue(from: item)
                let errorMessage = error?.localizedDescription
                Task { @MainActor [weak self, rawValue, errorMessage] in
                    self?.handleLoadedValue(rawValue, errorMessage: errorMessage)
                }
            }
            return
        }
        showFailure("Share a GitHub repository URL to Crabrix.")
    }

    nonisolated private static func stringValue(from item: NSSecureCoding?) -> String? {
        if let url = item as? URL {
            return url.absoluteString
        } else if let url = item as? NSURL {
            return url.absoluteString
        }
        return item as? String
    }

    private func handleLoadedValue(_ rawValue: String?, errorMessage: String?) {
        if let errorMessage {
            showFailure(errorMessage)
            return
        }
        guard let rawValue else {
            showFailure("The shared item does not contain a URL.")
            return
        }
        do {
            let reference = try SharedImportQueue.enqueue(rawValue)
            spinner.stopAnimating()
            statusLabel.text = "Saved to Crabrix"
            detailLabel.text = "\(reference.owner)/\(reference.repository) will import when Crabrix opens."
            doneButton.isHidden = false
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private func showFailure(_ message: String) {
        spinner.stopAnimating()
        statusLabel.text = "Could not save this link"
        detailLabel.text = message
        doneButton.isHidden = false
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
