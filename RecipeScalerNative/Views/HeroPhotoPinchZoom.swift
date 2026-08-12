//
//  HeroPhotoPinchZoom.swift
//  RecipeScalerNative
//
//  Inline pinch-to-zoom для hero-фотографий рецептов (spec 064).
//  Hero регистрирует UIImage + глобальный фрейм в `HeroPhotoZoomContext`;
//  `AppShellView` рисует зум-картинку в том же месте экрана (не из центра)
//  поверх tab bar / nav bar. Pinch и двухпальцевый pan — UIKit-жесты,
//  чтобы однопальцевый скролл карточки не перехватывался.
//

import SwiftUI
import UIKit

/// Снимок для overlay: одно `@Published` присваивание на тик жеста.
struct HeroPhotoZoomSnapshot {
    var image: UIImage?
    var heroFrame: CGRect = .zero
    var zoom: CGFloat = 1.0
    var offset: CGSize = .zero
    var pinchAnchor: UnitPoint = .center

    var isZooming: Bool { zoom > 1.001 }

    var dimOpacity: Double {
        guard isZooming else { return 0 }
        let t = Double((zoom - 1) / (HeroPhotoZoomMetrics.maxScale - 1))
        return HeroPhotoZoomMetrics.dimMax * min(max(t, 0), 1)
    }
}

enum HeroPhotoZoomMetrics {
    static let maxScale: CGFloat = 2.5
    static let dimMax: Double = 0.4
    /// FR-014: случайный микро-pinch не включает dim / hide original.
    static let minimumScaleDelta: CGFloat = 0.05
}

/// Observable только для overlay и hero, который его зумит. AppShell держит
/// `HeroPhotoZoomSession` через `@State`, не `@StateObject` — иначе tab tree
/// пересобирается на каждый scroll/pinch tick.
@MainActor
final class HeroPhotoZoomContext: ObservableObject {
    static let maxScale: CGFloat = HeroPhotoZoomMetrics.maxScale
    static let dimMax: Double = HeroPhotoZoomMetrics.dimMax
    static let minimumScaleDelta: CGFloat = HeroPhotoZoomMetrics.minimumScaleDelta

    @Published private(set) var snapshot = HeroPhotoZoomSnapshot()

    /// Per-hero layout/image: вкладки Recipes + Discover остаются смонтированными,
    /// поэтому один слот last-writer-wins ломал бы чужой bitmap/frame.
    private var frames: [ObjectIdentifier: CGRect] = [:]
    private var images: [ObjectIdentifier: UIImage] = [:]
    private var activeOwner: ObjectIdentifier?

    var isZooming: Bool { snapshot.isZooming }

    func register(owner: ObjectIdentifier, image: UIImage?) {
        if let image {
            images[owner] = image
        } else {
            images.removeValue(forKey: owner)
        }
        if snapshot.isZooming, activeOwner == owner {
            publish { $0.image = image }
        }
    }

    func unregister(owner: ObjectIdentifier) {
        images.removeValue(forKey: owner)
        frames.removeValue(forKey: owner)
        guard activeOwner == owner else { return }
        activeOwner = nil
        if snapshot.isZooming {
            publish { $0 = HeroPhotoZoomSnapshot() }
        }
    }

    func updateLiveFrame(owner: ObjectIdentifier, frame: CGRect) {
        frames[owner] = frame
        if snapshot.isZooming, activeOwner == owner, snapshot.heroFrame != frame {
            publish { $0.heroFrame = frame }
        }
    }

    func applyGesture(
        owner: ObjectIdentifier,
        zoom: CGFloat,
        offset: CGSize,
        anchor: UnitPoint
    ) {
        activeOwner = owner
        publish {
            $0.image = images[owner]
            $0.heroFrame = frames[owner] ?? .zero
            $0.zoom = clampedZoom(from: zoom)
            $0.offset = offset
            $0.pinchAnchor = anchor
        }
    }

    func endGesture(owner: ObjectIdentifier, animated: Bool) {
        guard activeOwner == owner else { return }
        let reset = {
            self.publish {
                $0.zoom = 1.0
                $0.offset = .zero
                $0.pinchAnchor = .center
            }
        }
        if animated {
            withAnimation(.smooth(duration: 0.20), reset)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, reset)
        }
    }

    func clampedZoom(from magnification: CGFloat) -> CGFloat {
        min(max(magnification, 1), Self.maxScale)
    }

    private func publish(_ mutate: (inout HeroPhotoZoomSnapshot) -> Void) {
        var next = snapshot
        mutate(&next)
        snapshot = next
    }
}

/// Не-Observable держатель: `@State` в AppShell не подписывается на pinch ticks.
@MainActor
final class HeroPhotoZoomSession {
    let context = HeroPhotoZoomContext()
}

private struct HeroPhotoZoomContextKey: EnvironmentKey {
    static let defaultValue: HeroPhotoZoomContext? = nil
}

extension EnvironmentValues {
    var heroPhotoZoomContext: HeroPhotoZoomContext? {
        get { self[HeroPhotoZoomContextKey.self] }
        set { self[HeroPhotoZoomContextKey.self] = newValue }
    }
}

private final class HeroPhotoZoomOwnerToken {}

/// Pinch + двухпальцевый pan на hero. Визуал живёт в корневом overlay.
struct HeroPhotoPinchZoomModifier: ViewModifier {
    var isEnabled: Bool
    var uiImage: UIImage?

    @Environment(\.heroPhotoZoomContext) private var ctx
    @State private var ownerToken = HeroPhotoZoomOwnerToken()

    func body(content: Content) -> some View {
        if let ctx {
            HeroPhotoPinchZoomObservedBody(
                content: content,
                ctx: ctx,
                owner: ObjectIdentifier(ownerToken),
                isEnabled: isEnabled,
                uiImage: uiImage
            )
        } else {
            content
        }
    }
}

/// Подписка на snapshot только у hero, не у AppShell.
private struct HeroPhotoPinchZoomObservedBody<Content: View>: View {
    let content: Content
    @ObservedObject var ctx: HeroPhotoZoomContext
    let owner: ObjectIdentifier
    var isEnabled: Bool
    var uiImage: UIImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .opacity(ctx.isZooming ? 0 : 1)
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { ctx.updateLiveFrame(owner: owner, frame: geo.frame(in: .global)) }
                        .onChange(of: geo.frame(in: .global)) { _, frame in
                            ctx.updateLiveFrame(owner: owner, frame: frame)
                        }
                }
            }
            .overlay {
                if isEnabled, uiImage != nil {
                    HeroPinchPanCatcher(
                        onChanged: { scale, offset, anchor in
                            ctx.applyGesture(
                                owner: owner,
                                zoom: scale,
                                offset: offset,
                                anchor: anchor
                            )
                        },
                        onEnded: {
                            ctx.endGesture(owner: owner, animated: !reduceMotion)
                        }
                    )
                    .allowsHitTesting(true)
                }
            }
            .task {
                guard isEnabled, let uiImage else { return }
                ctx.register(owner: owner, image: uiImage)
            }
            .onChange(of: uiImage) { _, newValue in
                if isEnabled, let newValue {
                    ctx.register(owner: owner, image: newValue)
                } else {
                    ctx.unregister(owner: owner)
                }
            }
            .onChange(of: isEnabled) { _, newValue in
                if !newValue {
                    ctx.unregister(owner: owner)
                } else if let uiImage {
                    ctx.register(owner: owner, image: uiImage)
                }
            }
            .onDisappear {
                ctx.unregister(owner: owner)
            }
    }
}

/// Прозрачный UIView: `UIPinchGestureRecognizer` + двухпальцевый `UIPanGestureRecognizer`.
private struct HeroPinchPanCatcher: UIViewRepresentable {
    var onChanged: (CGFloat, CGSize, UnitPoint) -> Void
    var onEnded: () -> Void

    func makeUIView(context: Context) -> HeroPinchPanView {
        let view = HeroPinchPanView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: HeroPinchPanView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }
}

private final class HeroPinchPanView: UIView, UIGestureRecognizerDelegate {
    var onChanged: ((CGFloat, CGSize, UnitPoint) -> Void)?
    var onEnded: (() -> Void)?

    private let pinch = UIPinchGestureRecognizer()
    private let pan = UIPanGestureRecognizer()
    private var pinchAnchor: UnitPoint = .center
    private var lastScale: CGFloat = 1
    private var didNotifyEnd = true
    private var hasActivated = false

    private var activationScale: CGFloat { 1 + HeroPhotoZoomMetrics.minimumScaleDelta }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pan.addTarget(self, action: #selector(handlePan(_:)))
        pinch.delegate = self
        pan.delegate = self
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pinch.cancelsTouchesInView = false
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer === pinch && other === pan)
            || (gestureRecognizer === pan && other === pinch)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === pan {
            let pinchLive = pinch.state == .began || pinch.state == .changed
            return pinchLive && pinch.scale >= activationScale
        }
        return true
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchAnchor = unitPoint(for: recognizer.location(in: self))
            publishIfActivated()
        case .changed:
            publishIfActivated()
        case .ended, .cancelled, .failed:
            finishIfIdle()
        default:
            break
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            if pinch.state != .began && pinch.state != .changed {
                pinchAnchor = unitPoint(for: recognizer.location(in: self))
            }
            publishIfActivated()
        case .changed:
            publishIfActivated()
        case .ended, .cancelled, .failed:
            finishIfIdle()
        default:
            break
        }
    }

    private func publishIfActivated() {
        if pinch.state == .began || pinch.state == .changed {
            lastScale = pinch.scale
        }
        guard lastScale >= activationScale else { return }
        hasActivated = true
        didNotifyEnd = false
        let translation = pan.translation(in: self)
        onChanged?(lastScale, CGSize(width: translation.x, height: translation.y), pinchAnchor)
    }

    private func finishIfIdle() {
        let pinchActive = pinch.state == .began || pinch.state == .changed
        let panActive = pan.state == .began || pan.state == .changed
        guard !pinchActive, !panActive, !didNotifyEnd else { return }
        didNotifyEnd = true
        lastScale = 1
        let shouldEnd = hasActivated
        hasActivated = false
        if shouldEnd {
            onEnded?()
        }
    }

    private func unitPoint(for location: CGPoint) -> UnitPoint {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return .center }
        return UnitPoint(x: location.x / w, y: location.y / h)
    }
}

extension View {
    func heroPhotoPinchZoom(isEnabled: Bool = true, uiImage: UIImage? = nil) -> some View {
        modifier(HeroPhotoPinchZoomModifier(isEnabled: isEnabled, uiImage: uiImage))
    }

    /// Корневой overlay: картинка в фрейме hero, scale из точки pinch, pan смещает.
    func heroPhotoZoomOverlay(_ ctx: HeroPhotoZoomContext) -> some View {
        overlay {
            HeroPhotoZoomOverlayHost(ctx: ctx)
        }
    }
}

/// Отдельный View с `@ObservedObject`: AppShell не должен наблюдать context.
private struct HeroPhotoZoomOverlayHost: View {
    @ObservedObject var ctx: HeroPhotoZoomContext

    var body: some View {
        let snap = ctx.snapshot
        if snap.isZooming {
            GeometryReader { overlayGeo in
                let overlayOrigin = overlayGeo.frame(in: .global).origin
                ZStack {
                    Color.black.opacity(snap.dimOpacity)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    if let image = snap.image, snap.heroFrame.width > 0 {
                        let midX = snap.heroFrame.midX - overlayOrigin.x
                        let midY = snap.heroFrame.midY - overlayOrigin.y
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: snap.heroFrame.width, height: snap.heroFrame.height)
                            .clipped()
                            .scaleEffect(snap.zoom, anchor: snap.pinchAnchor)
                            .offset(snap.offset)
                            .position(x: midX, y: midY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview("Pinch-zoom enabled") {
    ZStack {
        Color(.secondarySystemBackground)
        Image(systemName: "photo")
            .font(.system(size: 80))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: 400)
    .heroPhotoPinchZoom(isEnabled: true, uiImage: nil)
}

#Preview("Pinch-zoom disabled") {
    ZStack {
        Color(.secondarySystemBackground)
        Image(systemName: "photo")
            .font(.system(size: 80))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: 400)
    .heroPhotoPinchZoom(isEnabled: false, uiImage: nil)
}
#endif
