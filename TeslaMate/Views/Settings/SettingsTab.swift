import SwiftUI

struct SettingsTab: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var showSetupGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://grafana.yourdomain.com", text: $viewModel.serverURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("Grafana Service Account Token", text: $viewModel.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await viewModel.testAndAutoConfigure() }
                    } label: {
                        HStack {
                            if viewModel.connectionStatus == .testing {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Connecting & Auto-Configuring...")
                            } else {
                                Image(systemName: "sparkles")
                                Text("Test Connection & Auto-Discover")
                            }
                        }
                        .fontWeight(.semibold)
                    }
                    .disabled(viewModel.serverURL.isEmpty || viewModel.apiToken.isEmpty || viewModel.connectionStatus == .testing)

                    switch viewModel.connectionStatus {
                    case .idle:
                        EmptyView()
                    case .testing:
                        EmptyView()
                    case .success(let message):
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    case .error(let message):
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Grafana Server")
                } footer: {
                    Text("Enter your Grafana URL and a Service Account Token (Viewer role) from Grafana → Administration → Service accounts.")
                }

                if !viewModel.availableCars.isEmpty {
                    Section("Vehicle") {
                        Picker("Select Vehicle", selection: $viewModel.carID) {
                            ForEach(viewModel.availableCars) { car in
                                Text(car.displayName).tag(car.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: viewModel.carID) { _, _ in
                            Task { await viewModel.loadAll() }
                        }
                    }
                }

                Section("Manual / Advanced Settings") {
                    DisclosureGroup("Datasource UID & Car ID") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Datasource UID", text: $viewModel.datasourceUID)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            TextField("Car ID", value: $viewModel.carID, format: .number)
                                .keyboardType(.numberPad)

                            Button("Reload All Data") {
                                Task { await viewModel.loadAll() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Help & Guides") {
                    Button {
                        showSetupGuide = true
                    } label: {
                        Label("View Onboarding & Setup Guide", systemImage: "book.pages")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString)
                            .foregroundStyle(.secondary)
                    }

                    Text("TeslaMate iOS queries your PostgreSQL telemetry database through Grafana's API. No WebView or third-party cloud is used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showSetupGuide) {
                OnboardingView(
                    viewModel: viewModel,
                    isPresented: $showSetupGuide,
                    hasCompletedOnboarding: .constant(true)
                )
            }
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
