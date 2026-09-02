import SwiftUI
import MapKit

struct DriveMapView: View {
    let positions: [DrivePositionPoint]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showFullScreenMap = false

    private var coordinates: [CLLocationCoordinate2D] {
        positions.map(\.coordinate)
    }

    private var routeRect: MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.union(pointRect)
        }
        return rect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Route Map")
                    .font(.headline)
                Spacer()
                Button {
                    fitRoute()
                } label: {
                    Label("Fit Route", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)

                Button {
                    showFullScreenMap = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }

            if coordinates.isEmpty {
                Text("No GPS route points available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Map(position: $cameraPosition, interactionModes: .all) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 4)

                    if let start = coordinates.first {
                        Annotation("Start", coordinate: start) {
                            Circle()
                                .fill(.green)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }

                    if let end = coordinates.last {
                        Annotation("End", coordinate: end) {
                            Circle()
                                .fill(.red)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onAppear {
                    fitRoute()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showFullScreenMap) {
            FullScreenMapView(positions: positions)
        }
    }

    private func fitRoute() {
        guard let rect = routeRect else { return }
        cameraPosition = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15))
    }
}

struct FullScreenMapView: View {
    let positions: [DrivePositionPoint]
    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyleSelection: MapStyleOption = .standard

    enum MapStyleOption: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case imagery = "Satellite"
        case hybrid = "Hybrid"

        var id: String { rawValue }

        var mapStyle: MapStyle {
            switch self {
            case .standard: return .standard
            case .imagery: return .imagery
            case .hybrid: return .hybrid
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        positions.map(\.coordinate)
    }

    private var routeRect: MKMapRect? {
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for coord in coordinates {
            let point = MKMapPoint(coord)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.union(pointRect)
        }
        return rect
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, interactionModes: .all) {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, lineWidth: 5)

                    if let start = coordinates.first {
                        Annotation("Start", coordinate: start) {
                            ZStack {
                                Circle().fill(.green).frame(width: 20, height: 20)
                                Circle().stroke(.white, lineWidth: 2)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    if let end = coordinates.last {
                        Annotation("End", coordinate: end) {
                            ZStack {
                                Circle().fill(.red).frame(width: 20, height: 20)
                                Circle().stroke(.white, lineWidth: 2)
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
                .mapStyle(mapStyleSelection.mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapPitchToggle()
                }

                VStack(spacing: 8) {
                    Picker("Style", selection: $mapStyleSelection) {
                        ForEach(MapStyleOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: 220)

                    Button {
                        fitRoute()
                    } label: {
                        Label("Fit Route", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Drive Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                fitRoute()
            }
        }
    }

    private func fitRoute() {
        guard let rect = routeRect else { return }
        cameraPosition = .rect(rect.insetBy(dx: -rect.size.width * 0.15, dy: -rect.size.height * 0.15))
    }
}
