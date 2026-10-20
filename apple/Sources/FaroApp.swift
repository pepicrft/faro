import SwiftUI

@main
struct FaroApp: App {
    var body: some Scene {
        WindowGroup {
            FaroWelcomeView()
        }
        #if os(macOS)
        .defaultSize(width: 640, height: 480)
        #endif
    }
}

struct FaroWelcomeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "light.beacon.max.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(FaroCore.name)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(FaroCore.tagline)
                        .font(.title3)
                }

                Text(FaroCore.status)
                    .foregroundStyle(.secondary)

                Text("Version \(FaroCore.version)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 360)
        #endif
    }
}
