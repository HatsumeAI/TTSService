import AppKit
import SwiftUI

/// Settings panel shown on left click of the status item.
struct SettingsView: View {
    @Bindable var model: AppModel

    /// Which endpoint just flashed its "copied" checkmark, if any.
    @State private var copiedEndpoint: Endpoint.Kind?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                networkSection
                endpointsSection
                startupSection
            }
            .formStyle(.grouped)
            .disabled(model.status.locksSettings)

            Divider()

            footer
        }
        .frame(width: 460, height: 580)
        .task(id: copiedEndpoint) {
            guard copiedEndpoint != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            copiedEndpoint = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isRunning ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 26))
                .foregroundStyle(model.isRunning ? Color.green : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("SayTTS")
                    .font(.headline)
                Text(model.status.title)
                    .font(.subheadline)
                    .foregroundStyle(model.isRunning ? .green : .secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Sections

    private var networkSection: some View {
        Section {
            Toggle("Serve on local network", isOn: $model.serveOnLocalNetwork)

            LabeledContent("Address") {
                TextField("127.0.0.1", text: $model.host)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .disabled(!model.serveOnLocalNetwork)
            }

            LabeledContent("Port") {
                TextField("9000", text: $model.portText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: model.portText) { _, newValue in
                        let sanitized = PortValidator.sanitize(newValue)
                        if sanitized != newValue {
                            model.portText = sanitized
                        }
                    }
            }

            if let message = model.portValidation.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle("Require authentication", isOn: $model.requiresAuthentication)

            if model.requiresAuthentication {
                LabeledContent("Token") {
                    SecureField("Required", text: $model.token)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }

                if let message = model.tokenValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var endpointsSection: some View {
        Section {
            if model.endpoints.isEmpty {
                Text("Enter a valid port to see the endpoint URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.endpoints) { endpoint in
                    endpointRow(endpoint)
                }
            }
        }
    }

    private func endpointRow(_ endpoint: Endpoint) -> some View {
        HStack(spacing: 8) {
            Label {
                Text(endpoint.id.rawValue)
                    .font(.subheadline)
            } icon: {
                Image(systemName: endpoint.id.symbol)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(endpoint.url)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Button {
                copy(endpoint)
            } label: {
                Image(systemName: copiedEndpoint == endpoint.id ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Copy \(endpoint.id.rawValue) endpoint URL")
            .accessibilityLabel(
                copiedEndpoint == endpoint.id
                    ? "Copied \(endpoint.id.rawValue) URL"
                    : "Copy \(endpoint.id.rawValue) URL"
            )
        }
    }

    private func copy(_ endpoint: Endpoint) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(endpoint.url, forType: .string)
        copiedEndpoint = endpoint.id
    }

    private var startupSection: some View {
        Section("Startup") {
            Toggle("Start serving when SayTTS opens", isOn: $model.autoStart)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let detail = model.status.detail {
                Label(detail, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(detail)
            }

            Spacer(minLength: 0)

            Button {
                model.toggle()
            } label: {
                Text(buttonTitle)
                    .frame(minWidth: 72)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canToggle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var buttonTitle: String {
        switch model.status {
        case .running: "Stop"
        case .starting, .stopping: model.status.title
        case .stopped, .failed: "Start"
        }
    }

    /// Starting and stopping are transient, so the button stays live for them.
    private var canToggle: Bool {
        switch model.status {
        case .starting, .stopping, .running: true
        case .stopped, .failed: model.canStart
        }
    }
}
