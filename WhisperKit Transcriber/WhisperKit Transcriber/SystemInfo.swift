//
//  SystemInfo.swift
//  WhisperKitTranscriber
//
//  System information and GPU detection for compute unit optimization
//

import Foundation
import Metal

struct SystemInfo {
    // CPU Information
    static var cpuModel: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &model, &size, nil, 0)
        return String(cString: model)
    }

    static var cpuCores: Int {
        ProcessInfo.processInfo.processorCount
    }

    // GPU Information
    static var hasMetalSupport: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    static var gpuName: String? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        return device.name
    }

    // Apple Silicon specific
    static var isAppleSilicon: Bool {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        return size > 0
    }

    static var hasNeuralEngine: Bool {
        // Neural Engine is available on Apple Silicon Macs
        isAppleSilicon
    }

    // Memory Information
    static var totalMemory: Int64 {
        var size = MemoryLayout<Int64>.size
        var totalMemory: Int64 = 0
        sysctlbyname("hw.memsize", &totalMemory, &size, nil, 0)
        return totalMemory
    }

    static var totalMemoryGB: Double {
        Double(totalMemory) / (1024 * 1024 * 1024)
    }

    // Recommended compute unit based on hardware
    static var recommendedComputeUnit: ComputeUnit {
        if isAppleSilicon {
            return .cpuAndNeuralEngine  // Use ANE + CPU for Apple Silicon (most efficient)
        } else if hasMetalSupport {
            return .cpuAndGPU  // Intel Mac with discrete GPU
        } else {
            return .cpuOnly  // Fallback to CPU only
        }
    }

    // Performance capabilities summary
    static var performanceSummary: String {
        var summary = "CPU: \(cpuModel) (\(cpuCores) cores)\n"
        summary += "Memory: \(String(format: "%.1f", totalMemoryGB)) GB\n"

        if hasMetalSupport, let gpuName = gpuName {
            summary += "GPU: \(gpuName)\n"
        } else {
            summary += "GPU: Not available\n"
        }

        if isAppleSilicon {
            summary += "Apple Silicon: Yes (Neural Engine available)\n"
        } else {
            summary += "Apple Silicon: No\n"
        }

        summary += "Recommended: \(recommendedComputeUnit.displayName)"

        return summary
    }
}

enum ComputeUnit: String, CaseIterable, Identifiable {
    case all = "all"
    case cpuAndGPU = "cpuAndGPU"
    case cpuAndNeuralEngine = "cpuAndNeuralEngine"
    case cpuOnly = "cpuOnly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "All (CPU + GPU + Neural Engine)"
        case .cpuAndGPU:
            return "CPU + GPU"
        case .cpuAndNeuralEngine:
            return "CPU + Neural Engine (Recommended for Apple Silicon)"
        case .cpuOnly:
            return "CPU Only"
        }
    }

    var description: String {
        switch self {
        case .all:
            return "Uses all available compute units for maximum performance. May use more power."
        case .cpuAndGPU:
            return "Uses CPU and GPU (good for Intel Macs with discrete GPU)"
        case .cpuAndNeuralEngine:
            return "Uses CPU and Neural Engine (Apple Silicon optimized, most efficient)"
        case .cpuOnly:
            return "CPU only (slowest, most compatible, lowest power usage)"
        }
    }

    // WhisperKit CLI argument value
    var cliArgument: String {
        return rawValue
    }

    // Hardware compatibility check
    func isCompatible() -> Bool {
        switch self {
        case .all:
            return SystemInfo.hasMetalSupport && SystemInfo.hasNeuralEngine
        case .cpuAndGPU:
            return SystemInfo.hasMetalSupport
        case .cpuAndNeuralEngine:
            return SystemInfo.hasNeuralEngine
        case .cpuOnly:
            return true  // Always compatible
        }
    }

    var compatibilityWarning: String? {
        switch self {
        case .all:
            if !SystemInfo.hasNeuralEngine {
                return "Neural Engine not available. Will fall back to available compute units."
            }
            if !SystemInfo.hasMetalSupport {
                return "Metal/GPU not available. Will fall back to available compute units."
            }
            return nil
        case .cpuAndGPU:
            if !SystemInfo.hasMetalSupport {
                return "Metal/GPU not available on this system. Will fall back to CPU only."
            }
            return nil
        case .cpuAndNeuralEngine:
            if !SystemInfo.hasNeuralEngine {
                return "Neural Engine not available (requires Apple Silicon). Will fall back to CPU only."
            }
            return nil
        case .cpuOnly:
            return nil
        }
    }
}
