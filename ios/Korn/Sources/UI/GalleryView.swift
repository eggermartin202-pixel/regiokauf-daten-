import SwiftUI

struct GalleryView: View {
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if model.shots.isEmpty {
                    ContentUnavailableView("Noch keine Fotos", systemImage: "camera",
                                           description: Text("Deine entwickelten Aufnahmen erscheinen hier."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(model.shots, id: \.self) { url in
                                NavigationLink(value: url) { GalleryCell(url: url) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Galerie")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: URL.self) { ShotDetail(url: $0, model: model) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

private struct GalleryCell: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.white.opacity(0.08)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
            }
            .clipped()
            .task {
                image = await Task.detached { Thumbnail.load(url, maxPixel: 360) }.value
            }
    }
}

private struct ShotDetail: View {
    let url: URL
    @ObservedObject var model: CameraModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmDelete = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .task {
            image = await Task.detached { Thumbnail.load(url, maxPixel: 2400) }.value
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                ShareLink(item: url)
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Löschen")
            }
        }
        .confirmationDialog("Foto aus Korn löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                model.delete(url)
                dismiss()
            }
        } message: {
            Text("Die Kopie in der Fotomediathek bleibt erhalten.")
        }
    }
}
