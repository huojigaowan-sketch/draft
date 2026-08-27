import SwiftUI

struct LocalPolishButton: View {
    @Binding var text: String
    @State private var isWorking = false
    @State private var errorMessage = ""
    @State private var showingError = false

    var body: some View {
        Button {
            polish()
        } label: {
            if isWorking {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Label("本地整理", systemImage: "apple.intelligence")
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .disabled(
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || isWorking
                || !AppleTextService.availability.isAvailable
        )
        .help(AppleTextService.availability.label)
        .alert("无法整理文字", isPresented: $showingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func polish() {
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                text = try await AppleTextService.polish(text)
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

