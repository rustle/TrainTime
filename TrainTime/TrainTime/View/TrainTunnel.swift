import Observation
import SwiftUI

@Observable
final class TrainTunnelState {
    fileprivate var trainAnimationState = TrainAnimationState(middleCars: 2)
    fileprivate var tunnelOffset: CGFloat = 800
    fileprivate(set) var isComplete: Bool = false
}

struct TrainTunnel: View {
    @State var state = TrainTunnelState()

    var body: some View {
        ZStack {
            Rectangle()
            HStack(spacing: 0) {
                TunnelView {
                    TrainAnimation(state: state.trainAnimationState)
                }
                .frame(height: 90)
                .offset(x: state.tunnelOffset)
                .onAppear {
                    withAnimation(.spring(duration: 1.2,
                                          bounce: 0.2)) {
                        state.tunnelOffset = 0
                    } completion: {
                        state.trainAnimationState.isRunning = true
                    }
                }
                .onChange(of: state.trainAnimationState.isComplete) { _, newValue in
                    if newValue {
                        state.isComplete = true
                    }
                }
            }
        }
    }
}

#Preview {
    TrainTunnel(state: TrainTunnelState())
        .ignoresSafeArea()
        .foregroundStyle(.amtrakBlue)
}
