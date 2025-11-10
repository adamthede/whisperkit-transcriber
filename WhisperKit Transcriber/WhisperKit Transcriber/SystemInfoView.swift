//
//  SystemInfoView.swift
//  WhisperKitTranscriber
//
//  View for displaying system information and hardware capabilities
//

import SwiftUI

struct SystemInfoView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("System Information")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Performance Summary
                    GroupBox {
                        Text(SystemInfo.performanceSummary)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Hardware Summary", systemImage: "cpu")
                            .font(.headline)
                    }

                    // Hardware Capabilities
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            CapabilityRow(
                                icon: "memorychip",
                                title: "Metal Support",
                                isAvailable: SystemInfo.hasMetalSupport,
                                description: "GPU acceleration for graphics and compute"
                            )

                            CapabilityRow(
                                icon: "brain.head.profile",
                                title: "Neural Engine",
                                isAvailable: SystemInfo.hasNeuralEngine,
                                description: "Dedicated ML acceleration (Apple Silicon only)"
                            )

                            CapabilityRow(
                                icon: "laptopcomputer",
                                title: "Apple Silicon",
                                isAvailable: SystemInfo.isAppleSilicon,
                                description: "ARM-based Apple processors (M1, M2, M3, etc.)"
                            )
                        }
                    } label: {
                        Label("Capabilities", systemImage: "checkmark.circle")
                            .font(.headline)
                    }

                    // Performance Tips
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            TipRow(
                                icon: "sparkles",
                                text: "Apple Silicon Macs: Use 'CPU + Neural Engine' for best efficiency"
                            )
                            TipRow(
                                icon: "speedometer",
                                text: "Intel Macs with GPU: Use 'CPU + GPU' for faster processing"
                            )
                            TipRow(
                                icon: "battery.100",
                                text: "'CPU Only' mode uses least power but is slower"
                            )
                            TipRow(
                                icon: "chart.line.uptrend.xyaxis",
                                text: "Larger models benefit more from GPU/Neural Engine acceleration"
                            )
                            TipRow(
                                icon: "exclamationmark.triangle",
                                text: "Incompatible compute units will automatically fall back to CPU"
                            )
                        }
                        .font(.caption)
                    } label: {
                        Label("Performance Tips", systemImage: "lightbulb")
                            .font(.headline)
                    }

                    // Recommended Settings
                    GroupBox {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Recommended Compute Unit:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(SystemInfo.recommendedComputeUnit.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Close button
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 600, height: 550)
    }
}

// MARK: - Helper Views

struct CapabilityRow: View {
    let icon: String
    let title: String
    let isAvailable: Bool
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isAvailable ? .green : .red)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.blue)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    SystemInfoView()
}
