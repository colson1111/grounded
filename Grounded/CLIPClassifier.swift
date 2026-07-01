import CoreML
import CoreImage
import Accelerate
import Foundation

/// Loads MobileCLIP-S1 CoreML model + pre-computed category embeddings.
/// Thread-safe for concurrent calls to classify().
final class CLIPClassifier {
    static let shared = CLIPClassifier()

    private let model: MLModel
    /// category id → normalized 512-d embedding (row-major)
    private let categoryEmbeddings: [(id: String, vector: [Float])]
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static let inputSize = 256

    private init() {
        guard
            let modelURL = Bundle.main.url(forResource: "MobileCLIPImageEncoder", withExtension: "mlpackage"),
            let compiled = try? MLModel.compileModel(at: modelURL),
            let model = try? MLModel(contentsOf: compiled)
        else {
            fatalError("Failed to load MobileCLIPImageEncoder.mlpackage")
        }
        self.model = model

        guard
            let embURL = Bundle.main.url(forResource: "category_embeddings", withExtension: "json"),
            let data = try? Data(contentsOf: embURL),
            let dict = try? JSONDecoder().decode([String: [Float]].self, from: data)
        else {
            fatalError("Failed to load category_embeddings.json")
        }
        // Sort for deterministic order
        self.categoryEmbeddings = dict.sorted { $0.key < $1.key }.map { (id: $0.key, vector: $0.value) }
    }

    /// Returns top-k (categoryID, cosineSimilarity) pairs for the given pixel buffer.
    func classify(pixelBuffer: CVPixelBuffer, topK: Int = 10) -> [(id: String, similarity: Float)] {
        guard let resized = resized(pixelBuffer) else { return [] }
        guard let embedding = encode(resized) else { return [] }
        return topMatches(embedding: embedding, topK: topK)
    }

    // MARK: - Private

    private func resized(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: source)
        let size = CGSize(width: Self.inputSize, height: Self.inputSize)
        let scaleX = size.width / ciImage.extent.width
        let scaleY = size.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var output: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputSize,
            Self.inputSize,
            kCVPixelFormatType_32BGRA,
            nil,
            &output
        )
        guard let output else { return nil }
        ciContext.render(scaled, to: output)
        return output
    }

    private func encode(_ pixelBuffer: CVPixelBuffer) -> [Float]? {
        guard
            let input = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]),
            let output = try? model.prediction(from: input),
            let embFeature = output.featureValue(for: "embedding"),
            let multiArray = embFeature.multiArrayValue
        else { return nil }

        let count = multiArray.count
        var embedding = [Float](repeating: 0, count: count)
        // MLMultiArray may be FLOAT16; copy via NSNumber path
        for i in 0..<count {
            embedding[i] = multiArray[i].floatValue
        }
        // L2-normalize (model output should already be normalized, but guard against drift)
        var norm: Float = 0
        vDSP_dotpr(embedding, 1, embedding, 1, &norm, vDSP_Length(count))
        norm = sqrtf(norm)
        if norm > 1e-6 {
            var invNorm = 1.0 / norm
            vDSP_vsmul(embedding, 1, &invNorm, &embedding, 1, vDSP_Length(count))
        }
        return embedding
    }

    private func topMatches(embedding: [Float], topK: Int) -> [(id: String, similarity: Float)] {
        let n = vDSP_Length(embedding.count)
        var results = categoryEmbeddings.map { cat -> (id: String, similarity: Float) in
            var dot: Float = 0
            vDSP_dotpr(embedding, 1, cat.vector, 1, &dot, n)
            return (id: cat.id, similarity: dot)
        }
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK))
    }
}
