//
//  ShineCardView.swift
//  ShineCard
//

import SwiftUI
import MetalKit

// SwiftUI 桥接
struct ShineCardView: UIViewRepresentable {
    @Binding var touchLocation: CGPoint
    @Binding var isTouching: Bool
    
    func makeUIView(context: Context) -> ShineCardMetalView {
        let view = ShineCardMetalView()
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: ShineCardMetalView, context: Context) {
        uiView.touchLocation = touchLocation
        uiView.isTouching = isTouching
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ShineCardMetalViewDelegate {
        var parent: ShineCardView
        
        init(_ parent: ShineCardView) {
            self.parent = parent
        }
        
        func touchBegan(at location: CGPoint) {
            parent.touchLocation = location
            parent.isTouching = true
        }
        
        func touchMoved(at location: CGPoint) {
            parent.touchLocation = location
        }
        
        func touchEnded() {
            parent.isTouching = false
        }
    }
}

// 代理协议
protocol ShineCardMetalViewDelegate: AnyObject {
    func touchBegan(at location: CGPoint)
    func touchMoved(at location: CGPoint)
    func touchEnded()
}

// Metal 视图
class ShineCardMetalView: MTKView {
    weak var touchDelegate: ShineCardMetalViewDelegate?
    
    var touchLocation: CGPoint = .zero
    var isTouching: Bool = false
    
    private var renderer: ShineCardRenderer!
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        // 使用默认 Metal 设备
        self.device = MTLCreateSystemDefaultDevice()
        
        // 配置视图
        self.colorPixelFormat = .bgra8Unorm
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        
        // 创建渲染器
        renderer = ShineCardRenderer(device: device!, view: self)
        self.delegate = renderer
        
        // 添加触摸手势
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let normalized = normalizeLocation(location)
        
        switch gesture.state {
        case .began:
            touchDelegate?.touchBegan(at: normalized)
            renderer.touchBegan(at: normalized)
        case .changed:
            touchDelegate?.touchMoved(at: normalized)
            renderer.touchMoved(at: normalized)
        case .ended, .cancelled:
            touchDelegate?.touchEnded()
            renderer.touchEnded()
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        let normalized = normalizeLocation(location)
        
        touchDelegate?.touchBegan(at: normalized)
        renderer.touchBegan(at: normalized)
        
        // 延迟结束
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.touchDelegate?.touchEnded()
            self.renderer.touchEnded()
        }
    }
    
    private func normalizeLocation(_ location: CGPoint) -> CGPoint {
        return CGPoint(x: location.x / bounds.width, y: 1.0 - location.y / bounds.height)
    }
}
