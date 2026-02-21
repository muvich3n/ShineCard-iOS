//
//  ShineCardRenderer.swift
//  ShineCard
//
//  1:1 复刻 react-native-shine 渲染管线
//

import MetalKit
import MetalPerformanceShaders

// MARK: - Uniforms (1:1 对应 Metal 结构体)
struct Uniforms {
    // 基础参数
    var resolution: SIMD2<Float>      // 屏幕分辨率
    var rotation: SIMD2<Float>         // 旋转/倾斜 (对应 rot.xy)
    var time: Float                    // 时间
    
    // Holo 参数
    var holoDirectionDegree: Float     // 全息方向角度
    var holoShift: Float               // 偏移
    var holoRotationShiftPower: Float  // 旋转偏移强度
    var holoSize: Float                // 全息条纹大小
    var holoMultiplier: Float          // 条纹密度
    var holoEaseSize: Float            // 边缘过渡
    var holoVisibility: Float          // 可见度
    var holoSaturation: Float          // 饱和度
    
    // Glare 参数
    var glareIntensity: Float          // 光泽强度
    var glowPower: Float               // 光晕曲线
    var lightIntensity: Float          // 光源强度
    var hueBlendPower: Float           // 色相混合
    var hueShiftAngleMin: Float        // 色相偏移最小
    var hueShiftAngleMax: Float        // 色相偏移最大
    var glareColor: SIMD4<Float>       // 光泽颜色
    
    // 效果开关
    var enableHolo: Float              // 1.0 = 开启
    var enableGlare: Float             // 1.0 = 开启
    var enableDoubleHolo: Float        // 1.0 = 双层
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
    private var rotation: SIMD2<Float> = [0.0, 0.0]  // 模拟陀螺仪/触摸偏移
    private var startTime: Date = Date()
    
    // 效果参数 (可调整)
    var holoParams = HoloParams()
    var glareParams = GlareParams()
    var enableHolo: Bool = true
    var enableGlare: Bool = false  // 需要高斯模糊，默认关闭
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
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        
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
                // 创建对角线彩虹渐变
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
        }
        
        // 初始化高斯模糊管线
        blurPipeline = MPSImageGaussianBlur(device: device, sigma: 5.0)
    }
    
    // HSV 转 RGB 辅助函数
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
        // 将触摸位置映射到旋转参数
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchMoved(at location: CGPoint) {
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchEnded() {
        // 慢慢回到中心
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
            
            holoDirectionDegree: holoParams.directionDegree,
            holoShift: holoParams.shift,
            holoRotationShiftPower: holoParams.rotationShiftPower,
            holoSize: holoParams.size,
            holoMultiplier: holoParams.multiplier,
            holoEaseSize: holoParams.easeSize,
            holoVisibility: holoParams.visibility,
            holoSaturation: holoParams.saturation,
            
            glareIntensity: glareParams.intensity,
            glowPower: glareParams.glowPower,
            lightIntensity: glareParams.lightIntensity,
            hueBlendPower: glareParams.hueBlendPower,
            hueShiftAngleMin: glareParams.hueShiftAngleMin,
            hueShiftAngleMax: glareParams.hueShiftAngleMax,
            glareColor: glareParams.color,
            
            enableHolo: enableHolo ? 1.0 : 0.0,
            enableGlare: enableGlare ? 1.0 : 0.0,
            enableDoubleHolo: enableDoubleHolo ? 1.0 : 0.0
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        
        // 可选：执行高斯模糊（用于 glare 效果）
        if enableGlare, let blurredTexture = blurredTexture {
            let commandBuffer = commandQueue.makeCommandBuffer()!
            blurPipeline?.encode(commandBuffer: commandBuffer, sourceTexture: cardTexture, destinationTexture: blurredTexture)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        // 渲染
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(cardTexture, index: 0)
        renderEncoder.setFragmentTexture(blurredTexture, index: 1)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        // 绘制 (6个顶点，两个三角形)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
