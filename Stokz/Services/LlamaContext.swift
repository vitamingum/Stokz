import Foundation
import llama

// MARK: - Llama C API Bridging
// These functions bridge to the llama.cpp C library via the XCFramework

/// Errors that can occur during LLM operations
enum LlamaContextError: Error, LocalizedError {
    case couldNotInitializeContext
    case modelLoadFailed(String)
    case decodeFailed
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .couldNotInitializeContext: return "Could not initialize LLM context"
        case .modelLoadFailed(let path): return "Failed to load model at: \(path)"
        case .decodeFailed: return "LLM decode failed"
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        }
    }
}

/// Swift wrapper around llama.cpp context for text generation
/// Based on: https://github.com/ggml-org/llama.cpp/blob/master/examples/llama.swiftui/llama.cpp.swift/LibLlama.swift
actor LlamaContext {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch
    private var tokensList: [llama_token] = []
    private var temporaryInvalidCChars: [CChar] = []
    
    var isDone: Bool = false
    var nLen: Int32 = 512  // Max tokens to generate
    var nCur: Int32 = 0
    
    private init(model: OpaquePointer, context: OpaquePointer) {
        self.model = model
        self.context = context
        self.batch = llama_batch_init(512, 0, 1)
        
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        
        self.vocab = llama_model_get_vocab(model)
    }
    
    deinit {
        if let sampling = sampling {
            llama_sampler_free(sampling)
        }
        llama_batch_free(batch)
        if let context = context {
            llama_free(context)
        }
        if let model = model {
            llama_model_free(model)
        }
    }
    
    /// Create a new LlamaContext from a model file path
    static func create(modelPath: String) async throws -> LlamaContext {
        llama_backend_init()
        
        var modelParams = llama_model_default_params()
        
        #if targetEnvironment(simulator)
        modelParams.n_gpu_layers = 0
        print("LlamaContext: Running on simulator, GPU layers disabled")
        #else
        modelParams.n_gpu_layers = 99  // Use Metal GPU acceleration
        #endif
        
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaContextError.modelLoadFailed(modelPath)
        }
        
        let nThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        print("LlamaContext: Using \(nThreads) threads")
        
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 2048
        ctxParams.n_threads = Int32(nThreads)
        ctxParams.n_threads_batch = Int32(nThreads)
        
        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw LlamaContextError.couldNotInitializeContext
        }
        
        return LlamaContext(model: model, context: context)
    }
    
    /// Generate a completion for the given prompt
    func complete(prompt: String, maxTokens: Int32 = 128) async throws -> String {
        guard let context = context, let vocab = vocab, let sampling = sampling else {
            throw LlamaContextError.couldNotInitializeContext
        }
        
        // Reset state
        isDone = false
        nLen = maxTokens
        nCur = 0
        tokensList.removeAll()
        temporaryInvalidCChars.removeAll()
        
        // Tokenize the prompt
        tokensList = tokenize(text: prompt, addBos: true)
        print("LlamaContext: Tokenized \(tokensList.count) tokens from prompt")
        
        if tokensList.isEmpty {
            print("LlamaContext: ERROR - No tokens from prompt!")
            return ""
        }
        
        // Clear the batch
        batch.n_tokens = 0
        
        // Add tokens to batch
        for (i, token) in tokensList.enumerated() {
            addToBatch(token: token, pos: Int32(i), seqIds: [0], logits: i == tokensList.count - 1)
        }
        
        // Initial decode
        let decodeResult = llama_decode(context, batch)
        if decodeResult != 0 {
            print("LlamaContext: Initial decode failed with code \(decodeResult)")
            throw LlamaContextError.decodeFailed
        }
        
        nCur = batch.n_tokens
        print("LlamaContext: Initial decode done, nCur=\(nCur)")
        
        // Generate tokens
        var result = ""
        var tokenCount = 0
        
        while !isDone && nCur < nLen + Int32(tokensList.count) {
            // Sample next token
            let newTokenId = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
            
            // Check for end of generation
            if llama_vocab_is_eog(vocab, newTokenId) {
                print("LlamaContext: EOG token encountered after \(tokenCount) tokens")
                isDone = true
                break
            }
            
            // Convert token to text
            let tokenStr = tokenToString(token: newTokenId)
            result += tokenStr
            tokenCount += 1
            
            // Prepare next batch
            batch.n_tokens = 0
            addToBatch(token: newTokenId, pos: nCur, seqIds: [0], logits: true)
            
            nCur += 1
            
            // Decode
            if llama_decode(context, batch) != 0 {
                throw LlamaContextError.decodeFailed
            }
        }
        
        // Clear KV cache for next generation
        llama_kv_cache_clear(context)
        
        print("LlamaContext: Generated \(tokenCount) tokens, result length: \(result.count)")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Clear the context for fresh generation
    func clear() {
        tokensList.removeAll()
        temporaryInvalidCChars.removeAll()
        if let context = context {
            llama_kv_cache_clear(context)
        }
    }
    
    // MARK: - Private Helpers
    
    private func addToBatch(token: llama_token, pos: llama_pos, seqIds: [llama_seq_id], logits: Bool) {
        let idx = Int(batch.n_tokens)
        batch.token[idx] = token
        batch.pos[idx] = pos
        batch.n_seq_id[idx] = Int32(seqIds.count)
        for (i, seqId) in seqIds.enumerated() {
            batch.seq_id[idx]![i] = seqId
        }
        batch.logits[idx] = logits ? 1 : 0
        batch.n_tokens += 1
    }
    
    private func tokenize(text: String, addBos: Bool) -> [llama_token] {
        guard let vocab = vocab else { return [] }
        
        let utf8Count = text.utf8.count
        let nTokens = utf8Count + (addBos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: nTokens)
        defer { tokens.deallocate() }
        
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(nTokens), addBos, false)
        
        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        
        return swiftTokens
    }
    
    private func tokenToString(token: llama_token) -> String {
        guard let vocab = vocab else { return "" }
        
        let bufSize = 32
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: bufSize)
        defer { result.deallocate() }
        result.initialize(repeating: 0, count: bufSize)
        
        let nChars = llama_token_to_piece(vocab, token, result, Int32(bufSize), 0, false)
        
        if nChars < 0 {
            // Need more space
            let newSize = Int(-nChars)
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: newSize)
            defer { newResult.deallocate() }
            newResult.initialize(repeating: 0, count: newSize)
            
            let actualChars = llama_token_to_piece(vocab, token, newResult, Int32(newSize), 0, false)
            if actualChars > 0 {
                return String(cString: newResult)
            }
            return ""
        }
        
        if nChars > 0 {
            return String(cString: result)
        }
        
        return ""
    }
}
