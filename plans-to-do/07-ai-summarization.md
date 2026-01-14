# Implementation Plan: AI Summarization & Daily Digest

## Overview
Transform WhisperKit Transcriber from a simple utility into an intelligence tool by adding **AI Summarization**. This feature addresses the "Surveillance/Security" use case where users have dozens of video files per day and need a high-level summary of events rather than reading raw logs.

**Core Goal**: Aggregate transcripts (e.g., by day + camera) and generate a concise summary of the audio events.

## User Story
"As a user with 12 home security cameras, I want to see a single 'Daily Digest' that summarizes what happened yesterday across all feeds, highlighting unusual conversations or noises, instead of opening 50 individual transcript files."

## Technical Approach

### 1. Data Aggregation Strategy
We need a way to group "related" transcripts.
- **Grouping Key**: `Date (YYYY-MM-DD)` + `Source Directory` (assuming cameras are organized by folder).
- **Source**: Scan the `Exported Transcripts` directories or query the internal `completedTranscriptions` history.

### 2. AI Engine (Inference)
Since WhisperKit is a local-first, privacy-focused app, the summarization should ideally be local.
- **Option A: Local LLM (Recommended Goal)**
  - Use **MLX-Swift** (Apples machine learning framework) or **Llama.cpp**.
  - Model: `Llama-3-8B-Instruct` or `Phi-3-Mini` (smaller, faster).
  - Pros: Privacy, Offline, Free.
  - Cons: Requires high RAM (8GB+), large download (~4GB).
- **Option B: API Integration (MVP)**
  - OpenAI / Anthropic / Groq keys provided by user.
  - Pros: Easy to implement, lightweight app.
  - Cons: Costs money, privacy concerns for security footage.

**Decision**: Start with **Option B (API)** for rapid prototyping, but architect the system to plug in **Option A (Local MLX)** as the mature "Pro" feature.

### 3. Prompt Engineering
The system needs a robust system prompt to handle multiple inputs.
**Input**:
```text
[Camera 1 - 08:00 AM]: [Sound of wind]
[Camera 1 - 08:15 AM]: "Hey, did you leave the package?" "Yeah, on the porch."
[Camera 2 - 09:30 AM]: [Dog barking]
```
**Output Goal**:
> "At 8:15 AM on Camera 1, a delivery person confirmed leaving a package. Sporadic dog barking detected on Camera 2 at 9:30 AM."

## Implementation Steps

### Step 1: `SummarizationManager`
Create a manager to:
1.  Fetch completed transcriptions for a given time range.
2.  Format them into a single context window.
3.  Send to AI Service.

```swift
struct DailySummary {
    let date: Date
    let summary: String
    let keyEvents: [String]
}

class SummarizationManager: ObservableObject {
    func generateDailyDigest(for date: Date, files: [URL]) async throws -> DailySummary {
        // 1. Read files
        // 2. Concat text
        // 3. Call LLM
    }
}
```

### Step 2: UI - The "Insights" Tab
A new Tab in the main UI:
- **Calendar View**: Select a date.
- **Summary Card**: The AI generated text.
- **Source Links**: Clickable links to the original video/transcript files referenced.

### Step 3: Settings for "Auto-Summarize" (Future)
- "Automatically generate summary at 11:59 PM"
- "Context Length Limit" (to manage token costs/RAM).

## Dependencies
- **LLM Client**: Simple HTTP client for OpenAI format (compatible with local server wrappers like LM Studio/Ollama too).
- **Markdown Rendering**: For displaying the structured summary.

## Risks & Challenges
1.  **Context Window**: 12 cameras x 24 hours = Massive text.
    - *Mitigation*: We must pre-filter "Silence" or "No Speech" segments. Only send segments with actual tokens.
    - *Mitigation*: Recursive summarization (summarize each hour, then summarize the hours).
2.  **Hallucinations**: AI might invent events.
    - *Mitigation*: Use high temperature=0, provide "Citation" instruction ("Reference the timestamp").

## Timeline Estimate
- **Phase 1 (MVP)**: API-based summarization of selected files. (1-2 weeks)
- **Phase 2 (Aggregation)**: Auto-grouping by folder/date. (1 week)
- **Phase 3 (Local LLM)**: Integrating MLX for on-device inference. (2-3 weeks)
