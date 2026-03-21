import SwiftUI

struct TunnelView<Content: View>: View {
    let content: Content
    let tunnelColor: Color
    let apertureSize: CGFloat

    init(tunnelColor: Color = .black,
         apertureSize: CGFloat = 60,
         @ViewBuilder content: () -> Content) {
        self.tunnelColor = tunnelColor
        self.apertureSize = apertureSize
        self.content = content()
    }

    var body: some View {
        ZStack {
            tunnelColor
                .mask {
                    HStack(spacing: 0) {
                        Rectangle()
                        Circle()
                            .frame(width: apertureSize, height: apertureSize)
                            .offset(x: -apertureSize / 2)
                            .blendMode(.destinationOut)
                        Spacer(minLength: 0)
                    }
                    .padding(0)
                }
                .compositingGroup()

            content

            tunnelColor
                .mask {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .frame(width: apertureSize)
                            .overlay(alignment: .leading) {
                                Circle()
                                    .frame(width: apertureSize, height: apertureSize)
                                    .offset(x: -apertureSize / 2)
                                    .blendMode(.destinationOut)
                            }
                    }
                    .compositingGroup()
                }
        }
    }
}

#Preview {
    TunnelView(tunnelColor: .green,
               apertureSize: 100) {
        TrainAnimation(middleCars: 2)
    }
        .frame(height: 120)
}
