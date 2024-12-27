import MetalKit
import ModelIO
import SwiftUI

struct ContentView: View {
    var body: some View {
        MetalView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Metal view wrapper
struct MetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let metalView = MTKView()
        metalView.delegate = context.coordinator
        metalView.device = MTLCreateSystemDefaultDevice()
        metalView.clearColor = MTLClearColor(red: 0.2, green: 0.3, blue: 0.3, alpha: 1.0)
        metalView.colorPixelFormat = .bgra8Unorm

        // Load USDZ file
        if let url = Bundle.main.url(forResource: "your_model", withExtension: "usdz") {
            context.coordinator.loadUSDZ(url: url)
        }

        return metalView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
    }

    func makeCoordinator() -> Renderer {
        Renderer(metalView: MTKView())
    }
}

// Renderer class to handle Metal setup and drawing
class Renderer: NSObject, MTKViewDelegate {
    var device: MTLDevice
    var commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer?
    var vertexCount: Int = 0
    var meshes: [MTKMesh] = []

    init(metalView: MTKView) {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        device = dev
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        commandQueue = queue

        super.init()

        createPipelineState(metalView: metalView)
    }

    func createPipelineState(metalView: MTKView) {
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertexShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        if let firstMesh = meshes.first {
            // Use the vertex descriptor that was set up during mesh loading
            pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(
                firstMesh.vertexDescriptor)
        }

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
            let renderPassDescriptor = view.currentRenderPassDescriptor
        else {
            return
        }

        let commandBuffer = commandQueue.makeCommandBuffer()
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor)

        renderEncoder?.setRenderPipelineState(pipelineState)

        // Draw each mesh
        for mesh in meshes {
            for vertexBuffer in mesh.vertexBuffers {
                renderEncoder?.setVertexBuffer(
                    vertexBuffer.buffer,
                    offset: vertexBuffer.offset,
                    index: 0)
            }

            // Draw each submesh
            for submesh in mesh.submeshes {
                renderEncoder?.drawIndexedPrimitives(
                    type: submesh.primitiveType,
                    indexCount: submesh.indexCount,
                    indexType: submesh.indexType,
                    indexBuffer: submesh.indexBuffer.buffer,
                    indexBufferOffset: submesh.indexBuffer.offset)
            }
        }

        renderEncoder?.endEncoding()
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }

    func loadUSDZ(url: URL) {
        let allocator = MTKMeshBufferAllocator(device: device)

        let asset = MDLAsset(
            url: url,
            vertexDescriptor: nil,
            bufferAllocator: allocator)

        do {
            let meshObjects = asset.childObjects(of: MDLMesh.self)
            for case let mdlMesh as MDLMesh in meshObjects {
                let mdlVertexDescriptor = mdlMesh.vertexDescriptor

                // Create a Metal vertex descriptor that matches the MDL format
                let mtlVertexDescriptor = MTLVertexDescriptor()

                // Track the total stride for each buffer
                var strides: [Int: Int] = [:]

                // First pass: calculate strides for each buffer
                for (_, attribute) in mdlVertexDescriptor.attributes.enumerated() {
                    guard let attr = attribute as? MDLVertexAttribute else { continue }
                    let bufferIndex = Int(attr.bufferIndex)
                    let size = attr.format.size
                    let offset = Int(attr.offset)
                    strides[bufferIndex] = max(strides[bufferIndex] ?? 0, offset + size)
                }

                // Second pass: set up Metal attributes
                for (index, attribute) in mdlVertexDescriptor.attributes.enumerated() {
                    guard let attr = attribute as? MDLVertexAttribute else { continue }
                    let bufferIndex = Int(attr.bufferIndex)

                    mtlVertexDescriptor.attributes[index].format = attr.format.mtlFormat
                    mtlVertexDescriptor.attributes[index].offset = Int(attr.offset)
                    mtlVertexDescriptor.attributes[index].bufferIndex = bufferIndex

                    mtlVertexDescriptor.layouts[bufferIndex].stride = strides[bufferIndex] ?? 0
                    mtlVertexDescriptor.layouts[bufferIndex].stepFunction = .perVertex
                    mtlVertexDescriptor.layouts[bufferIndex].stepRate = 1
                }

                // Create new MDLVertexDescriptor and copy attributes
                mdlMesh.vertexDescriptor = MDLVertexDescriptor()
                mdlMesh.vertexDescriptor.attributes = mdlVertexDescriptor.attributes
                mdlMesh.vertexDescriptor.layouts = mdlVertexDescriptor.layouts

                do {
                    let mtkMesh = try MTKMesh(mesh: mdlMesh, device: device)
                    self.meshes.append(mtkMesh)
                } catch {
                    print("Failed to create MTKMesh: \(error)")
                }
            }
        }
    }
}

// Add this extension to handle MDL to MTL format conversion
extension MDLVertexFormat {
    var size: Int {
        switch self {
        case .float: return MemoryLayout<Float>.size
        case .float2: return MemoryLayout<SIMD2<Float>>.size
        case .float3: return MemoryLayout<SIMD3<Float>>.size
        case .float4: return MemoryLayout<SIMD4<Float>>.size
        case .uChar4: return MemoryLayout<SIMD4<UInt8>>.size
        // Add other cases as needed
        default: return 0
        }
    }

    var mtlFormat: MTLVertexFormat {
        switch self {
        case .float: return .float
        case .float2: return .float2
        case .float3: return .float3
        case .float4: return .float4
        case .uChar4: return .uchar4
        case .uChar4Normalized: return .uchar4Normalized
        // Add other cases as needed
        default: return .float
        }
    }
}

#Preview {
    ContentView()
}
