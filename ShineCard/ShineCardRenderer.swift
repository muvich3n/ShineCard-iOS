//
//  ShineCardRenderer.swift
//  ShineCard
//

import MetalKit

// Uniforms 结构（与 shader 对应）
struct Uniforms {
    var touchPosition: SIMD2<Float>
    var isTouching: Float
    var time: Float
    var resolution: SIMD2<Float>
}

class ShineCardRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var vertexBuffer: MTLBuffer!
    private var uniformsBuffer: MTLBuffer!
    private var texture: MTLTexture?
    private var samplerState: MTLSamplerState!
    
    // 状态
    private var touchPosition: SIMD2<Float> = [0.5, 0.5]
    private var isTouching: Float = 0.0
    private var startTime: Date = Date()
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue
        
        // 加载 shader
        let library: MTLLibrary
        do {
            // 从 bundle 加载 .metal 文件编译后的库
            library = try device.makeDefaultLibrary(bundle: Bundle.main)
        } catch {
            // 如果没有编译好的库，直接 fatalError
            fatalError("Could not create default library: \(error)")
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            fatalError("Could not find shader functions")
        }
        
        // 创建 pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
        
        super.init()
        
        // 创建 sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
        // 创建 uniforms buffer
        uniformsBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: .storageModeShared)
        
        // 初始化 uniforms 为零
        var emptyUniforms = Uniforms(
            touchPosition: [0.5, 0.5],
            isTouching: 0.0,
            time: 0.0,
            resolution: [1.0, 1.0]
        )
        memcpy(uniformsBuffer.contents(), &emptyUniforms, MemoryLayout<Uniforms>.size)
        
        // 加载纹理
        loadTexture()
    }
    
    // 加载卡片纹理
    private func loadTexture() {
        // 创建一个渐变色卡片作为默认纹理
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 512,
            height: 512,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        texture = device.makeTexture(descriptor: textureDescriptor)
        
        // 填充渐变色数据
        var pixels: [UInt8] = []
        for y in 0..<512 {
            for x in 0..<512 {
                let r = UInt8(50 + (x * 205) / 512)  // 深蓝紫渐变
                let g = UInt8(50)
                let b = UInt8(100 + (y * 155) / 512)
                let a: UInt8 = 255
                pixels.append(contentsOf: [r, g, b, a])
            }
        }
        
        pixels.withUnsafeBytes { ptr in
            texture?.replace(
                region: MTLRegionMake2D(0, 0, 512, 512),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: 512 * 4
            )
        }
    }
    
    // MARK: - Touch Handling
    
    func touchBegan(at location: CGPoint) {
        touchPosition = [Float(location.x), Float(location.y)]
        isTouching = 1.0
    }
    
    func touchMoved(at location: CGPoint) {
        touchPosition = [Float(location.x), Float(location.y)]
    }
    
    func touchEnded() {
        isTouching = 0.0
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 处理尺寸变化
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        // 更新 uniforms
        let elapsedTime = Float(Date().timeIntervalSince(startTime))
        let drawableSize = view.drawableSize
        var uniforms = Uniforms(
            touchPosition: touchPosition,
            isTouching: isTouching,
            time: elapsedTime,
            resolution: [Float(drawableSize.width), Float(drawableSize.height)]
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        
        // 创建 command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // 设置渲染状态
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(texture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // 绘制（三角形带，4个顶点）
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
