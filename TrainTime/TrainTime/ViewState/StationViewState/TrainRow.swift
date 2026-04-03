struct TrainRow: Identifiable, Sendable, Comparable {
    static func < (lhs: TrainRow,
                   rhs: TrainRow) -> Bool {
        lhs.stop.schArr < rhs.stop.schArr
    }
    let id: String
    let train: Train
    let stop: Stop
    init(trainAtStop: TrainAtStop) {
        self.train = trainAtStop.train
        self.stop = trainAtStop.stop
        self.id = train.trainID + stop.code
    }
}
