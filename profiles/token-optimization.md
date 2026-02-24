# CLAUDE.md — Token Optimization

## Purpose

Minimize token usage while preserving correctness, clarity, and structural integrity.
Designed for high-frequency usage, CI environments, large monorepos, and cost-sensitive systems.

---

## Core Principles

### 1. Compression First

* Prefer concise explanations over verbose narratives.
* Avoid repetition.
* Avoid restating the problem unless necessary.
* Use structured lists instead of long paragraphs.

### 2. Deterministic Output

* No decorative language.
* No emojis.
* No storytelling.
* No unnecessary context expansion.

### 3. Structured Responses

* Use bullet points.
* Use short code blocks.
* Avoid long-form essays.

### 4. No Redundant Summaries

* Do not end with summaries unless explicitly requested.
* Do not repeat user input.

### 5. Precision Over Exploration

* Provide direct answers.
* Avoid speculative branches unless asked.

---

## Output Style

* Technical
* Compact
* Minimalistic
* Low-token density

---

## When To Use

* CI pipelines
* Automated refactoring
* Code generation
* Large file analysis
* API response generation
* High-volume agent loops

---

## Forbidden Behaviors

* Motivational tone
* Conversational padding
* Excessive formatting
* Over-explaining

---

## Optimization Heuristics

* Prefer tables only if they reduce token count.
* Prefer code examples over long prose.
* Use implicit assumptions when safe.
* Avoid repeating constraints.

---

## Target Metric

Minimize tokens per useful unit of information.
