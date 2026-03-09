import os
import SwiftUI
import UIKit

#if USE_COLLECTION_VIEW
struct StationListCollectionViewHost: UIViewRepresentable {
    @State var state: StationListState
    var onSelect: (StationRow) -> Void
    var onRefresh: (() async -> Void)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)

        let layout = UICollectionViewCompositionalLayout.list(using: config)
        let collectionView = UICollectionView(frame: .zero,
                                              collectionViewLayout: layout)
        collectionView.delegate = context.coordinator

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator,
                                 action: #selector(Coordinator.refresh),
                                 for: .valueChanged)
        collectionView.refreshControl = refreshControl

        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, StationRow> { cell, _, row in
            cell.contentConfiguration = UIHostingConfiguration { StationCellView(row: row) }
            cell.accessories = [.disclosureIndicator()]
        }

        context.coordinator.dataSource = UICollectionViewDiffableDataSource<Int, StationRow>(collectionView: collectionView) { cv, indexPath, row in
            cv.dequeueConfiguredReusableCell(using: cellRegistration,
                                             for: indexPath,
                                             item: row)
        }

        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView,
                      context: Context) {
        context.coordinator.updateSnapshot(rows: state.filteredRows ?? state.allRows)
    }

    class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: StationListCollectionViewHost
        var dataSource: UICollectionViewDiffableDataSource<Int, StationRow>?
        var isRefreshing = false

        init(_ parent: StationListCollectionViewHost) {
            self.parent = parent
        }

        func updateSnapshot(rows: [StationRow]) {
            Logger.view.debug("Update Snapshot")
            var snapshot = NSDiffableDataSourceSnapshot<Int, StationRow>()
            snapshot.appendSections([0])
            snapshot.appendItems(rows,
                                 toSection: 0)
            dataSource?.apply(snapshot,
                              animatingDifferences: !isRefreshing)
        }

        func collectionView(_ collectionView: UICollectionView,
                            didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath,
                                        animated: true)
            if let item = dataSource?.itemIdentifier(for: indexPath) {
                parent.onSelect(item)
            }
        }

        @objc func refresh(_ sender: UIRefreshControl) {
            Task { @MainActor in
                await parent.onRefresh()
                sender.endRefreshing()
            }
        }
    }
}
#endif // USE_COLLECTION_VIEW
