import MapKit
import SwiftUI

struct StationLocationView: View {
    let station: Station
    var body: some View {
        List {
            if !station.formattedPostalAddress.isEmpty {
                Text(station.formattedPostalAddress)
                    .font(.body)
            }
            if let location = station.location {
                let coordinate = location.coordinate
                let region = MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
                let map = Map(initialPosition: .region(region),
                              interactionModes: []) {
                    Marker(
                        station.name ?? station.code,
                        coordinate: coordinate
                    )
                }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
#if os(tvOS)
                map
#else
                Button {
                    let placemark = MKPlacemark(coordinate: coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = station.name ?? station.code
                    mapItem.openInMaps()
                } label: {
                    map
                }
                .buttonStyle(.plain)
#endif
            }
        }
        .navigationTitle(station.name ?? station.code)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        StationLocationView(station: .init(
            name: "Utica",
            code: "UCA",
            lat: 43.103892,
            lon: -75.223434,
            address1: "321 Main Street",
            city: "Utica",
            zip: "13501",
            trainIdentifiers: []
        ))
    }
}
#endif
