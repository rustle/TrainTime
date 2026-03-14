struct TrainRow: Identifiable, Sendable, Comparable {
    static func < (lhs: TrainRow,
                   rhs: TrainRow) -> Bool {
        lhs.stop.schArr < rhs.stop.schArr
    }
    let id: String
    let train: TTTrain
    let stop: Stop
    init(train: TTTrain,
         stop: Stop) {
        self.train = train
        self.stop = stop
        self.id = train.trainID
    }
}
