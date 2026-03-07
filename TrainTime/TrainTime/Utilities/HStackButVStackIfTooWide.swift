import SwiftUI

struct HStackButVStackIfTooWide<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                content()
            }
            VStack(alignment: .leading) {
                content()
            }
        }
    }
}
