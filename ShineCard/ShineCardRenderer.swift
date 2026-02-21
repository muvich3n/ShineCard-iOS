//
//  ShineCardRenderer.swift
//  ShineCard
//
//  1:1 复刻 react-native-shine 渲染管线
//

import MetalKit
import MetalPerformanceShaders

// MARK: - Uniforms
// 注意：必须与 Metal shader 中的结构体完全一致
// 内存布局: 按 16 字节对齐
struct Uniforms {
    // 基础参数 (32 bytes)
    var resolution: SIMD2<Float>      // offset 0
    var rotation: SIMD2<Float>         // offset 8
    var time: Float                    // offset 16
    var _padding1: Float = 0           // offset 20 (对齐)
    var _padding2: Float = 0           // offset 24
    var _padding3: Float = 0           // offset 28
    
    // Holo 参数 (36 bytes, 按 16 对齐到 48)
    var holoDirectionDegree: Float     // offset 32
    var holoShift: Float               // offset 36
    var holoRotationShiftPower: Float  // offset 40
    var holoSize: Float                // offset 44
    var holoMultiplier: Float          // offset 48
    var holoEaseSize: Float            // offset 52
    var holoVisibility: Float          // offset 56
    var holoSaturation: Float          // offset 60
    var _padding4: Float = 0           // offset 64
    var _padding5: Float = 0           // offset 68
    var _padding6: Float = 0           // offset 72
    var _padding7: Float = 0           // offset 76
    
    // Glare 参数 (48 bytes)
    var glareIntensity: Float          // offset 80
    var glowPower: Float               // offset 84
    var lightIntensity: Float          // offset 88
    var hueBlendPower: Float           // offset 92
    var hueShiftAngleMin: Float        // offset 96
    var hueShiftAngleMax: Float        // offset 100
    var _padding8: Float = 0           // offset 104 (填充到 16 对齐)
    var _padding9: Float = 0           // offset 108
    var glareColor: SIMD4<Float>       // offset 112 (16 对齐)
    
    // 效果开关 (16 bytes)
    var enableHolo: Float              // offset 128
    var enableGlare: Float             // offset 132
    var enableDoubleHolo: Float        // offset 136
    var _padding10: Float = 0          // offset 140
    
    // 总大小: 144 bytes
}

class ShineCardRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var uniformsBuffer: MTLBuffer!
    private var cardTexture: MTLTexture?
    private var blurredTexture: MTLTexture?
    private var samplerState: MTLSamplerState!
    private var blurPipeline: MPSImageGaussianBlur?
    
    // 状态
    private var rotation: SIMD2<Float> = [0.0, 0.0]
    private var startTime: Date = Date()
    
    // 效果参数
    var holoParams = HoloParams()
    var glareParams = GlareParams()
    var enableHolo: Bool = true
    var enableGlare: Bool = false
    var enableDoubleHolo: Bool = true
    
    struct HoloParams {
        var directionDegree: Float = 45.0
        var shift: Float = 0.0
        var rotationShiftPower: Float = 0.5
        var size: Float = 0.15
        var multiplier: Float = 8.0
        var easeSize: Float = 0.3
        var visibility: Float = 0.8
        var saturation: Float = 0.9
    }
    
    struct GlareParams {
        var intensity: Float = 2.0
        var glowPower: Float = 2.5
        var lightIntensity: Float = 1.3
        var hueBlendPower: Float = 0.5
        var hueShiftAngleMin: Float = -30.0
        var hueShiftAngleMax: Float = 30.0
        var color: SIMD4<Float> = [1.0, 0.98, 0.95, 1.0]
    }
    
    init(device: MTLDevice, view: MTKView) {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue
        
        // 加载 shader
        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle.main)
        } catch {
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
        let uniformsSize = MemoryLayout<Uniforms>.size
        print("Uniforms size: \(uniformsSize) bytes")
        uniformsBuffer = device.makeBuffer(length: uniformsSize, options: .storageModeShared)
        
        // 加载纹理
        loadTextures(size: CGSize(width: 512, height: 512))
    }
    
    // MARK: - 纹理加载
    
    private func loadTextures(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        
        cardTexture = device.makeTexture(descriptor: textureDescriptor)
        blurredTexture = device.makeTexture(descriptor: textureDescriptor)
        
        // 创建彩虹渐变纹理
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(x + y) / Float(width + height)
                let hue = t * 360.0
                let rgb = hsvToRGB(h: hue, s: 0.8, v: 0.6)
                
                pixels.append(UInt8(rgb.0 * 255))
                pixels.append(UInt8(rgb.1 * 255))
                pixels.append(UInt8(rgb.2 * 255))
                pixels.append(255)
            }
        }
        
        pixels.withUnsafeBytes { ptr in
            cardTexture?.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: width * 4
            )
            blurredTexture?.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        
        blurPipeline = MPSImageGaussianBlur(device: device, sigma: 5.0)
    }
    
    private func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
        let c = v * s
        let x = c * (1.0 - abs(fmod(h / 60.0, 2.0) - 1.0))
        let m = v - c
        
        let (r, g, b): (Float, Float, Float)
        switch Int(h / 60.0) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        
        return (r + m, g + m, b + m)
    }
    
    // MARK: - 触摸处理
    
    func touchBegan(at location: CGPoint) {
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchMoved(at location: CGPoint) {
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchEnded() {
        rotation = [0.0, 0.0]
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if size.width > 0 && size.height > 0 {
            loadTextures(size: size)
        }
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let cardTexture = cardTexture else {
            return
        }
        
        let elapsedTime = Float(Date().timeIntervalSince(startTime))
        let drawableSize = view.drawableSize
        
        // 更新 uniforms
        var uniforms = Uniforms(
            resolution: [Float(drawableSize.width), Float(drawableSize.height)],
            rotation: rotation,
            time: elapsedTime,
            _padding1: 0, _padding2: 0, _padding3: 0,
            
            holoDirectionDegree: holoParams.directionDegree,
            holoShift: holoParams.shift,
            holoRotationShiftPower: holoParams.rotationShiftPower,
            holoSize: holoParams.size,
            holoMultiplier: holoParams.multiplier,
            holoEaseSize: holoParams.easeSize,
            holoVisibility: holoParams.visibility,
            holoSaturation: holoParams.saturation,
            _padding4: 0, _padding5: 0, _padding6: 0, _padding7: 0,
            
            glareIntensity: glareParams.intensity,
            glowPower: glareParams.glowPower,
            lightIntensity: glareParams.lightIntensity,
            hueBlendPower: glareParams.hueBlendPower,
            hueShiftAngleMin: glareParams.hueShiftAngleMin,
            hueShiftAngleMax: glareParams.hueShiftAngleMax,
            _padding8: 0, _padding9: 0,
            glareColor: glareParams.color,
            
            enableHolo: enableHolo ? 1.0 : 0.0,
            enableGlare: enableGlare ? 1.0 : 0.0,
            enableDoubleHolo: enableDoubleHolo ? 1.0 : 0.0,
            _padding10: 0
        )
        
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        
        // 渲染
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(cardTexture, index: 0)
        if let blurredTexture = blurredTexture {
            renderEncoder.setFragmentTexture(blurredTexture, index: 1)
        }
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
