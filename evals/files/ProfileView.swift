import SwiftUI
import Combine

final class ProfileModel: ObservableObject {
    @Published var name = ""
    @Published var tags: [String] = []
    @Published var isExpanded = false

    func load() {
        name = "Taylor"
        tags = ["swift", "ios", "swift"]
    }
}

struct ProfileView: View {
    @StateObject private var model = ProfileModel()
    @State private var headerWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading) {
            Text(model.name)
                .font(.title)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { headerWidth = proxy.size.width }
                    }
                )

            Text("Header width: \(Int(headerWidth))")

            if model.isExpanded {
                ForEach(model.tags.indices, id: \.self) { index in
                    Text(model.tags[index])
                }
                .transition(.opacity)
            }

            Button(model.isExpanded ? "Hide tags" : "Show tags") {
                model.isExpanded.toggle()
            }
        }
        .animation(.easeInOut, value: model.isExpanded)
        .onAppear { model.load() }
    }
}
