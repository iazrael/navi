//
//  ImagePreviewView.swift
//  Navi
//
//  Image preview component shown above the chat input when an image is selected.
//

import PhotosUI
import SwiftUI

struct ImagePreviewView: View {
    @Binding var selectedImage: UIImage?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let image = selectedImage {
                // Thumbnail preview
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("已选择图片")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("移除") {
                        selectedImage = nil
                        onRemove()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    ImagePreviewView(selectedImage: .constant(nil), onRemove: {})
}
