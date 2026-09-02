import SwiftUI
import MapKit

struct ChargeLocationMapView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String?

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showFullScreenMap = false

    private static let initialSpanMeters: Double = 3500

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Charging Location")
                    .font(.headline)
                Spacer()
                Button {
                    centerCamera()
                } label: {
                    Label("Center", systemImage: "location.circle")
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

            Map(position: $cameraPosition, interactionModes: .all) {
                Marker(locationName ?? "Charging Station", systemImage: "bolt.car.fill", coordinate: coordinate)
                    .tint(.green)
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                centerCamera()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showFullScreenMap) {
            FullScreenChargeMapView(coordinate: coordinate, locationName: locationName)
        }
    }

    private func centerCamera() {
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.initialSpanMeters,
            longitudinalMeters: Self.initialSpanMeters
        ))
    }
}

struct FullScreenChargeMapView: View {
    let coordinate: CLLocationCoordinate2D
    let locationName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyleSelection: FullScreenMapView.MapStyleOption = .standard

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, interactionModes: .all) {
                    Marker(locationName ?? "Charging Station", systemImage: "bolt.car.fill", coordinate: coordinate)
                        .tint(.green)
                }
                .mapStyle(mapStyleSelection.mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapPitchToggle()
                }

                VStack(spacing: 8) {
                    Picker("Style", selection: $mapStyleSelection) {
                        ForEach(FullScreenMapView.MapStyleOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: 220)

                    Button {
                        centerCamera()
                    } label: {
                        Label("Center Station", systemImage: "location.circle")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("Charging Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                centerCamera()
            }
        }
    }

    private func centerCamera() {
        cameraPosition = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 4000,
            longitudinalMeters: 4000
        ))
    }
}
