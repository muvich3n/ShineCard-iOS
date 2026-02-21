//
//  ShineCardRenderer.swift
//  ShineCard
//
//  1:1 复刻 react-native-shine 渲染管线
//

import MetalKit
import MetalPerformanceShaders

// MARK: - Uniforms
struct Uniforms {
    var resolution: SIMD2<Float>
    var rotation: SIMD2<Float>
    var time: Float
    var _padding1: Float
    var _padding2: Float
    var _padding3: Float
    
    var holoDirectionDegree: Float
    var holoShift: Float
    var holoRotationShiftPower: Float
    var holoSize: Float
    var holoMultiplier: Float
    var holoEaseSize: Float
    var holoVisibility: Float
    var holoSaturation: Float
    var _padding4: Float
    var _padding5: Float
    var _padding6: Float
    var _padding7: Float
    
    var glareIntensity: Float
    var glowPower: Float
    var lightIntensity: Float
    var hueBlendPower: Float
    var hueShiftAngleMin: Float
    var hueShiftAngleMax: Float
    var _padding8: Float
    var _padding9: Float
    var glareColor: SIMD4<Float>
    
    var enableHolo: Float
    var enableGlare: Float
    var enableDoubleHolo: Float
    var _padding10: Float
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
    
    private var rotation: SIMD2<Float> = [0.0, 0.0]
    private var startTime: Date = Date()
    
    var holoParams = HoloParams()
    var glareParams = GlareParams()
    var enableHolo: Bool = true
    var enableGlare: Bool = false
    var enableDoubleHolo: Bool = true
    
    struct HoloParams {
        var directionDegree: Float = 45.0
        var shift: Float = 0.0
        var rotationShiftPower: Float = 0.3
        var size: Float = 0.08
        var multiplier: Float = 4.0
        var easeSize: Float = 0.5
        var visibility: Float = 0.5
        var saturation: Float = 0.8
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
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
        let uniformsSize = MemoryLayout<Uniforms>.size
        print("Uniforms size: \(uniformsSize) bytes")
        uniformsBuffer = device.makeBuffer(length: uniformsSize, options: .storageModeShared)
        
        loadTextures(size: CGSize(width: 512, height: 512))
    }
    
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
        
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let t = Float(y) / Float(height)
                let r = UInt8(30 + t * 20)
                let g = UInt8(20 + t * 15)
                let b = UInt8(60 + t * 40)
                pixels.append(r)
                pixels.append(g)
                pixels.append(b)
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
        
        let i = Int(h / 60.0) % 6
        switch i {
        case 0: return (r: c + m, g: x + m, b: m)
        case 1: return (r: x + m, g: c + m, b: m)
        case 2: return (r: m, g: c + m, b: x + m)
        case 3: return (r: m, g: x + m, b: c + m)
        case 4: return (r: x + m, g: m, b: c + m)
        default: return (r: c + m, g: m, b: x + m)
        }
    }
    
    func touchBegan(at location: CGPoint) {
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchMoved(at location: CGPoint) {
        rotation = [Float(location.x) * 2.0 - 1.0, Float(location.y) * 2.0 - 1.0]
    }
    
    func touchEnded() {
        rotation = [0.0, 0.0]
    }
    
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
