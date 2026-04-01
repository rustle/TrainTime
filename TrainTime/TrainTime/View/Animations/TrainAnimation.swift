import Observation
import SwiftUI

enum TrainPosition: Equatable {
    case here
    case there
}

@Observable
final class TrainAnimationState {
    var middleCars: Int
    fileprivate var trackPhase: CGFloat = 0
    fileprivate var vibrate = false
    fileprivate var trainDriveAwayOffset: CGFloat = 0
    var position: TrainPosition = .here
    fileprivate(set) var isRunning: Bool = false
    init(middleCars: Int) {
        self.middleCars = middleCars
    }
}

struct TrainAnimation: View {
    private struct Tracks: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0,
                                  y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width,
                                     y: rect.midY))
            return path
        }
    }

    @State private(set) var state: TrainAnimationState
    @State private var containerWidth: CGFloat = 0

    init(state: TrainAnimationState) {
        self.state = state
    }

    init(middleCars: Int) {
        state = .init(middleCars: middleCars)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: -1) {
                Group {
                    Image(systemName: "train.side.rear.car")
                    ForEach(0..<state.middleCars, id: \.self) { _ in
                        Image(systemName: "train.side.middle.car")
                    }
                    Image(systemName: "train.side.front.car")
                }
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .trainGradientStop1,
                                  location: 0.1),
                            .init(color: .trainGradientStop2,
                                  location: 0.2),
                            .init(color: .trainGradientStop3,
                                  location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .drawingGroup()
            .offset(x: state.trainDriveAwayOffset,
                    y: state.vibrate ? 2 : 0)
            .animation(
                state.vibrate ? .easeInOut(duration: 0.1).repeatForever() : .default,
                value: state.vibrate
            )
            .animation(
                .easeIn(duration: 1.5),
                value: state.trainDriveAwayOffset
            )
            Tracks()
                .stroke(style: StrokeStyle(lineWidth: 4,
                                           dash: [10, 10],
                                           dashPhase: state.trackPhase))
                .foregroundStyle(Color.trainTracks)
                .frame(height: 4)
                .animation(
                    state.position == .there ?
                        .default :
                        .linear(duration: 0.3)
                            .repeatForever(autoreverses: false),
                    value: state.trackPhase
                )
                .padding(.top, -2)
        }
        .offset(x: -10)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            containerWidth = $0
        }
        .onChange(of: state.position) { _, newValue in
            if newValue == .there {
                driveAway()
            } else if newValue == .here {
                goBack()
            }
        }
        .onAppear {
            state.vibrate = true
            state.trackPhase = 20
        }
    }

    private func driveAway() {
        state.isRunning = true
        withAnimation(.none) {
            state.vibrate = false
            state.trackPhase = 0
        }
        withAnimation {
            state.trainDriveAwayOffset = containerWidth
        } completion: {
            state.isRunning = false
        }
    }
    
    private func goBack() {
        state.isRunning = true
        withAnimation(.none) {
            state.vibrate = true
            state.trackPhase = 20
        }
        withAnimation {
            state.trainDriveAwayOffset = 0
        } completion: {
            state.isRunning = false
        }
    }
}

#Preview {
    let state = TrainAnimationState(middleCars: 3)
    VStack {
        TrainAnimation(state: state)
        TrainAnimation(state: state)
        TrainAnimation(state: state)
        TrainAnimation(state: state)
    }
    Button(state.position == .here ?
        "Drive Away" :
        "Go Back"
    ) {
        if state.position == .here {
            state.position = .there
        } else {
            state.position = .here
        }
    }
    .disabled(state.isRunning)
}
