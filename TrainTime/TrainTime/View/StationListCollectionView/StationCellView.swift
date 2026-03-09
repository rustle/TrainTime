import SwiftUI

#if USE_COLLECTION_VIEW
struct StationCellView: View {
    let row: StationRow

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(.headline)
                Spacer()
                Text(row.station.code)
                    .font(.caption2.monospaced().smallCaps())
            }
        }
    }
}

#Preview {
    StationCellView(row:
            .init(station: .init(name: "Utica",
                                 code: "UCA",
                                 trainIdentifiers: [])
            )
    )
}
#endif // USE_COLLECTION_VIEW
