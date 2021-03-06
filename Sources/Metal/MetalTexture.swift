//
//  MetalTexture.swift
//  Pods
//
//  Created by kintan on 2018/6/14.
//

import MetalKit
public final class MetalTexture {
    public static var share = MetalTexture()
    private var textureCache: CVMetalTextureCache?
    private let device: MTLDevice
    init() {
        device = MetalRender.share.device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    public func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture]? {
        var textures = [MTLTexture]()
        let formats: [MTLPixelFormat]
        if pixelBuffer.planeCount == 3 {
            formats = [.r8Unorm, .r8Unorm, .r8Unorm]
        } else if pixelBuffer.planeCount == 2 {
            formats = [.r8Unorm, .rg8Unorm]
        } else {
            formats = [.bgra8Unorm]
        }
        for index in 0 ..< pixelBuffer.planeCount {
            let width = pixelBuffer.widthOfPlane(at: index)
            let height = pixelBuffer.heightOfPlane(at: index)
            if let texture = texture(pixelBuffer: pixelBuffer, planeIndex: index, pixelFormat: formats[index], width: width, height: height) {
                textures.append(texture)
            }
        }
        return textures
    }

    private func texture(pixelBuffer: CVPixelBuffer, planeIndex: Int, pixelFormat: MTLPixelFormat, width: Int, height: Int) -> MTLTexture? {
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache!, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &cvTextureOut)
        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        return inputTexture
    }

    func textures(pixelFormat: OSType, width: Int, height: Int, bytes: [UnsafeMutablePointer<UInt8>?], bytesPerRows: [Int32]) -> [MTLTexture]? {
        var planeCount = 3
        var widths = Array(repeating: width, count: 3)
        var heights = Array(repeating: height, count: 3)
        var formats = Array(repeating: MTLPixelFormat.r8Unorm, count: 3)
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8Planar:
            widths[1] = width / 2
            widths[2] = width / 2
            heights[1] = height / 2
            heights[2] = height / 2
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            planeCount = 2
            widths[1] = width / 2
            heights[1] = height / 2
            formats[1] = .rg8Unorm
        default:
            planeCount = 1
            formats[0] = .bgra8Unorm
        }
        var textures = [MTLTexture]()
        for i in 0 ..< planeCount {
            let key = "MTLTexture" + [Int(formats[i].rawValue), widths[i], heights[i]].description
            let texture = ObjectPool.share.object(class: MTLTexture.self, key: key) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[i], width: widths[i], height: heights[i], mipmapped: false)
                return self.device.makeTexture(descriptor: descriptor)!
            }
            texture.replace(region: MTLRegionMake2D(0, 0, widths[i], heights[i]), mipmapLevel: 0, withBytes: bytes[i]!, bytesPerRow: Int(bytesPerRows[i]))
            textures.append(texture)
        }
        return textures
    }

    public func comeback(textures: [MTLTexture]) {
        textures.forEach { texture in
            ObjectPool.share.comeback(item: texture, key: texture.key)
        }
    }

    public func flush() {
        if let textureCache = textureCache {
            CVMetalTextureCacheFlush(textureCache, 0)
        }
        ObjectPool.share.removeValue(forKey: "MTLTexture")
    }
}

extension MTLTexture {
    var key: String {
        return "MTLTexture" + [Int(pixelFormat.rawValue), width, height].description
    }
}
