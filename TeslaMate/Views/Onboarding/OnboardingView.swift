import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var isPresented: Bool
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentStep = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $currentStep) {
                WelcomeOnboardingStep {
                    withAnimation {
                        currentStep = 1
                    }
                }
                .tag(0)

                SetupGuideOnboardingStep(
                    viewModel: viewModel,
                    onFinish: {
                        hasCompletedOnboarding = true
                        isPresented = false
                    }
                )
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .navigationTitle(currentStep == 0 ? "Welcome" : "Connect Grafana")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(currentStep == 0 ? "Skip" : "Close") {
                        hasCompletedOnboarding = true
                        isPresented = false
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WelcomeOnboardingStep: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 88, height: 88)
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    Text("TeslaMate for iOS")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Your self-hosted Tesla telemetry dashboard, beautifully native on iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "map.fill",
                        color: .blue,
                        title: "Full Drive Analytics",
                        description: "Interactive GPS route maps, elevation profiles, speed & acceleration curves."
                    )

                    FeatureRow(
                        icon: "bolt.car.fill",
                        color: .green,
                        title: "Charging Insights",
                        description: "Track charging rates, battery curves, costs, and charging efficiency."
                    )

                    FeatureRow(
                        icon: "lock.shield.fill",
                        color: .indigo,
                        title: "100% Private & Direct",
                        description: "Communicates directly with your self-hosted Grafana instance. No third-party servers."
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 24)

                Button {
                    onContinue()
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SetupGuideOnboardingStep: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Step 1: Create a Service Account")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        StepItem(number: "1", text: "Open your Grafana instance in your browser.")
                        StepItem(number: "2", text: "Go to Administration → Users and access → Service accounts.")
                        StepItem(number: "3", text: "Click Add service account, name it 'TeslaMate iOS', set role to Viewer, and click Generate token.")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Step 2: Connect")
                        .font(.headline)

                    VStack(spacing: 12) {
                        TextField("https://grafana.yourdomain.com", text: $viewModel.serverURL)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()

                        SecureField("Grafana Service Account Token", text: $viewModel.apiToken)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task { await viewModel.testAndAutoConfigure() }
                        } label: {
                            HStack {
                                if viewModel.connectionStatus == .testing {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("Connecting & Discovering...")
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Connect & Auto-Discover")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
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
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        case .error(let message):
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    onFinish()
                } label: {
                    Text(viewModel.isConfigured ? "Continue to Dashboard" : "Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!viewModel.isConfigured)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .padding()
        }
    }
}

struct StepItem: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.blue, in: Circle())
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
