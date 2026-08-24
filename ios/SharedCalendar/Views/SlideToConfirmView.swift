import SwiftUI

/// A "slide to confirm" control, similar to iOS's slide-to-power-off, used as
/// a deliberate second confirmation before a destructive action actually runs.
struct SlideToConfirmView: View {
    let label: String
    let onConfirm: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isConfirming = false
    @State private var trackWidth: CGFloat = 280
    private let thumbSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.red.opacity(0.15))
                .frame(height: thumbSize)
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, thumbSize)
            Circle()
                .fill(Color.red)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    if isConfirming {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "chevron.right.2")
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            dragOffset = min(max(0, value.translation.width), maxOffset)
                        }
                        .onEnded { _ in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            if maxOffset > 0 && dragOffset > maxOffset * 0.85 {
                                dragOffset = maxOffset
                                isConfirming = true
                                Task { await onConfirm() }
                            } else {
                                withAnimation(.spring) { dragOffset = 0 }
                            }
                        }
                )
        }
        .frame(height: thumbSize)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { trackWidth = proxy.size.width }
                    // onAppear alone can catch a transitional (too-narrow)
                    // size when this view mounts mid-animation, e.g. inside
                    // a sheet that's still sliding into place — that stale
                    // width then permanently caps how far the thumb can
                    // travel, short of the capsule's actual right edge.
                    .onChange(of: proxy.size.width) { _, newWidth in
                        trackWidth = newWidth
                    }
            }
        )
        .listRowInsets(EdgeInsets())
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
