# TeslaMate for iOS

<p align="center">
  <strong>A modern, privacy-first native iOS client for self-hosted TeslaMate telemetry.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2017.0%2B-blue?style=flat-square&logo=apple" alt="iOS Platform" />
  <img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20%26%20Swift%20Charts-purple?style=flat-square" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Maps-MapKit-green?style=flat-square" alt="MapKit" />
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" alt="License" />
</p>

---

## ⚡ Overview

**TeslaMate for iOS** is a fast, native SwiftUI application designed to connect directly to your self-hosted **TeslaMate** telemetry database via Grafana's API. 

It provides rich drive routes, granular charging curves, interactive telemetry scrubbing, and instant startup caching—with **zero third-party cloud intermediaries**.

---

## ✨ Features

### 📊 Native Dashboard
- **Live Status & Metrics**: Battery SoC %, rated range, odometer, and last update timestamp.
- **Daily Distance Chart**: 14-day interactive bar chart with exact mile markers above each day.
- **Daily Charging Chart**: 14-day area chart showing daily kWh additions with interactive points.
- **Instant Launch**: Local synchronous cache renders previous data immediately on launch with background refresh (zero UI freezing).

### 🚗 Drive Analytics
- **Trip History**: Infinite scrolling list of recorded drives with addresses, duration, distance, and top speeds.
- **Interactive Route Maps**: MapKit polyline rendering of exact GPS drive tracks with start/end pin annotations, route-fitting, and a full-screen interactive map with standard/satellite/hybrid views.
- **Scrubbable Telemetry Charts**: Press and hold on any chart to scrub along the timeline:
  - 🏎️ **Speed Curve** (mph)
  - ⚡ **Power & Regen Curve** (kW acceleration vs regeneration)
  - 🏔️ **Elevation Profile** (ft)
  - 🔋 **Battery SoC & Range Progression** (%)

### ⚡ Charging Intelligence
- **Session History**: Detailed charging logs including kWh added, energy used, efficiency %, and cost.
- **Station Location Maps**: MapKit station pin with neighborhood context and full-screen view.
- **Charging Telemetry Charts**: Press and hold to inspect exact values at any point during a session:
  - 🔌 **Charging Power Curve** (Peak kW rate)
  - 🔋 **Battery SoC & Estimated Range**
  - 📈 **Cumulative Energy Added** (kWh)
  - ⚡ **Voltage & Current** (V / A)

### 🪄 Zero-Friction Auto-Discovery
- Connect simply by providing your **Grafana Server URL** and a **Service Account Token**.
- The app automatically queries `/api/datasources` to detect the TeslaMate PostgreSQL database UID.
- Automatically enumerates registered vehicles (`cars` table) and offers a multi-vehicle switcher.
- Includes a step-by-step onboarding guide on first launch.

---

## 🏗️ Architecture & Project Structure

The project follows a clean, modular SwiftUI architecture:

```
TeslaMate/
├── Models/
│   ├── VehicleModels.swift         # VehicleSummary, DailyValue, CarInfo
│   ├── DriveModels.swift           # DriveSummary, DrivePositionPoint
│   ├── ChargeModels.swift          # ChargeSummary, ChargePoint
│   └── GrafanaModels.swift         # GrafanaDatasource, GrafanaRow, GrafanaQuery
├── Services/
│   ├── GrafanaClient.swift         # Grafana REST client & SQL execution
│   ├── DataCache.swift             # UserDefaults synchronous caching
│   ├── URLBuilder.swift            # URL sanitization and normalization
│   └── Extensions.swift            # Unit conversions (.miles, .fahrenheit) & Errors
├── ViewModels/
│   └── DashboardViewModel.swift    # @MainActor ObservableObject coordinating state & queries
└── Views/
    ├── ContentView.swift           # Root TabView & onboarding presentation
    ├── Dashboard/
    │   ├── DashboardTab.swift       # Dashboard overview
    │   ├── MetricsCards.swift       # Quick status metrics cards
    │   ├── DailyDistanceChart.swift # Daily distance bar chart
    │   └── DailyChargingChart.swift # Daily charging area chart
    ├── Drives/
    │   ├── DrivesTab.swift          # Drives list
    │   ├── DriveDetailView.swift    # Detailed drive metrics
    │   ├── DriveMapView.swift       # MapKit route polyline & full-screen modal
    │   └── DriveTelemetryCharts.swift # Speed, Power, Elevation, Battery charts
    ├── Charging/
    │   ├── ChargingTab.swift        # Charging sessions list
    │   ├── ChargeDetailView.swift   # Detailed charging metrics
    │   ├── ChargeLocationMapView.swift # Station map & full-screen modal
    │   └── ChargeTelemetryCharts.swift # Power, Battery, Energy, V/A charts
    ├── Settings/
    │   └── SettingsTab.swift        # Connection settings & vehicle picker
    └── Onboarding/
        └── OnboardingView.swift     # First-launch setup guide & wizard
```

---

## 🚀 Getting Started

### 1. Prerequisites
- A running [TeslaMate](https://github.com/teslamate-org/teslamate) instance with Grafana accessible over your local network, VPN (e.g. Tailscale / WireGuard), or reverse proxy.

### 2. Generate a Grafana Service Account Token
1. Open your Grafana instance in a web browser.
2. Navigate to **Administration** → **Users and access** → **Service accounts**.
3. Click **Add service account**, name it `TeslaMate iOS`, and set the role to **Viewer**.
4. Click **Generate token** and copy the generated token (`glsa_...`).

### 3. Connect the App
1. Launch **TeslaMate for iOS**.
2. When the onboarding guide appears, paste your **Grafana URL** and **Service Account Token**.
3. Tap **"Connect & Auto-Discover"**.
4. Once connected, tap **"Continue to Dashboard"**!

---

## 🛠️ Building & Requirements

- **iOS Deployment Target**: iOS 17.0+
- **Xcode**: Xcode 16.0+
- **Swift**: Swift 6.0

### Build from Command Line
```bash
xcodebuild -scheme TeslaMate -destination 'platform=iOS Simulator,name=iPhone 17' build
```

---

## 🔒 Privacy & Security

- **Direct Communication**: Telemetry is fetched directly between your device and your Grafana instance.
- **No Third-Party Servers**: No external tracking, telemetry analytics, or intermediate cloud servers are used.
- **Read-Only Access**: Uses a Grafana *Viewer* service account token to strictly query historical tables without write permissions.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

