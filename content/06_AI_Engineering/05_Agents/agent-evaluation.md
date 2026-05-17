---
title: 05 - Agent Evaluation
description: "Agent evaluation measures whether agents complete tasks correctly — trajectory evaluation checks if the agent took the right steps; final answer evaluation checks output quality; LLM-as-judge scores responses when ground truth is unavailable; test datasets must include diverse failure cases."
tags: [agent-evaluation, trajectory, llm-as-judge, benchmarks, test-dataset, layer-4, ai]
status: draft
difficulty: intermediate
layer: 4
domain: ai
created: 2026-05-17
---

# Agent Evaluation

> Agent evaluation measures whether agents complete tasks correctly — trajectory evaluation checks if the agent took the right steps; final answer evaluation checks output quality; LLM-as-judge scores responses when ground truth is unavailable; test datasets must include diverse failure cases.

---

## Quick Reference

**Core idea:**
- **Final answer evaluation**: compare agent output to expected output — works when ground truth exists
- **Trajectory evaluation**: check if the agent took the right sequence of tool calls — catches correct-answer-wrong-path issues
- **LLM-as-judge**: use an LLM to score agent responses on criteria (accuracy, helpfulness, safety) — required when ground truth is ambiguous
- Test dataset: a collection of inputs with expected outputs or evaluation criteria — 50-100 diverse examples minimum
- `langsmith` — LangChain's evaluation and tracing platform; `pytest` works for deterministic evaluations

**Tricky points:**
- Agents are non-deterministic — the same input may produce different tool call sequences; evaluation must account for this
- LLM-as-judge is itself an LLM — it has biases (verbose answers score higher, first-listed option preferred); use reference answers to anchor scoring
- Trajectory evaluation is strict — it fails if the agent uses a different (but valid) path; use it only when the path matters, not just the outcome
- Latency and cost are first-class metrics for agents — a correct answer after 20 tool calls may be worse than a slightly-worse answer after 3
- Eval dataset must include edge cases: empty inputs, tool failures, ambiguous requests, multi-step tasks

---

## What It Is

Evaluating agents is harder than evaluating chains — a chain has deterministic outputs, an agent has variable-length trajectories with multiple tool calls. "Did the agent answer correctly?" is often not enough — did it use the right tools? Was the path efficient? Did it handle tool failures gracefully?

Evaluation is the mechanism that converts "it seems to work" into "it works on 87% of test cases with a p50 latency of 2.3s."

---

## How It Actually Works

Final answer evaluation (deterministic):
```python
import pytest
from langchain_core.messages import HumanMessage

test_cases = [
    {"input": "What is 2+2?", "expected": "4"},
    {"input": "What is the capital of France?", "expected": "Paris"},
]

@pytest.mark.parametrize("case", test_cases)
def test_agent_final_answer(case, agent):
    result = agent.invoke({"messages": [HumanMessage(content=case["input"])]})
    final_answer = result["messages"][-1].content
    assert case["expected"].lower() in final_answer.lower()
```

LLM-as-judge evaluation:
```python
from langchain_anthropic import ChatAnthropic
from langchain_core.prompts import ChatPromptTemplate

judge_llm = ChatAnthropic(model="claude-sonnet-4-6")

judge_prompt = ChatPromptTemplate.from_template("""
Evaluate this agent response on a scale of 1-5.

Question: {question}
Expected: {expected}
Agent response: {response}

Score criteria:
5 - Correct, complete, concise
3 - Partially correct or too verbose
1 - Wrong or harmful

Respond with only the number.
""")

judge_chain = judge_prompt | judge_llm

def evaluate_response(question: str, expected: str, response: str) -> int:
    result = judge_chain.invoke({
        "question": question,
        "expected": expected,
        "response": response,
    })
    return int(result.content.strip())
```

Trajectory evaluation:
```python
def evaluate_trajectory(result: dict, expected_tools: list[str]) -> bool:
    """Check if the agent used the expected tools in order."""
    tool_calls_made = []
    
    for message in result["messages"]:
        if hasattr(message, "tool_calls") and message.tool_calls:
            for tc in message.tool_calls:
                tool_calls_made.append(tc["name"])
    
    return tool_calls_made == expected_tools

# Example: research task should always search before summarizing
result = agent.invoke({"messages": [HumanMessage(content="Research X")]})
assert evaluate_trajectory(result, expected_tools=["web_search", "summarize"])
```

Batch evaluation across test dataset:
```python
from concurrent.futures import ThreadPoolExecutor

def run_evaluation(test_cases: list[dict], agent) -> dict:
    scores = []
    
    def evaluate_case(case):
        result = agent.invoke({"messages": [HumanMessage(content=case["input"])]})
        final_answer = result["messages"][-1].content
        score = evaluate_response(case["input"], case["expected"], final_answer)
        return score
    
    with ThreadPoolExecutor(max_workers=5) as executor:
        scores = list(executor.map(evaluate_case, test_cases))
    
    return {
        "mean_score": sum(scores) / len(scores),
        "pass_rate": sum(1 for s in scores if s >= 4) / len(scores),
    }
```

---

## How It Connects

Agent evaluation is required before deploying any agent system built with LangGraph or LangChain.
[[agents|Agents]]

LLM-as-judge relies on the same structured output patterns used in production agents.
[[structured-output|Structured Output]]

---

## Common Misconceptions

Misconception 1: "Pass/fail on expected output is sufficient."
Reality: Agents often produce correct outputs via wrong paths (wasted tool calls), or produce outputs that match the expected answer string but are misleading in context. Multi-dimensional evaluation (correctness, efficiency, safety) gives a more complete picture.

Misconception 2: "LLM-as-judge is objective."
Reality: LLM judges have known biases — they prefer longer, more confident-sounding answers and may favor responses from the same model family. Always include human-verified reference answers for calibration.

---

## Why It Matters in Practice

Minimum viable evaluation framework:
1. **Test dataset**: 50 inputs, annotated with expected outcomes or quality criteria
2. **Metric**: LLM-as-judge score 1-5 + binary pass/fail for critical requirements (safety, factual accuracy)
3. **Regression tests**: run evaluation before and after changes; flag score drops >5%
4. **Cost/latency tracking**: log tokens used and wall time per test case

---

## Interview Angle

Common question forms:
- "How do you evaluate an LLM agent?"
- "What metrics do you use for agent evaluation?"

Answer frame: Two main approaches — final answer evaluation (compare to ground truth, needs test dataset) and LLM-as-judge (LLM scores responses on criteria, handles open-ended outputs). Trajectory evaluation checks tool call sequences. Also measure: latency, token cost, tool call count. Build a test dataset of 50-100 diverse cases including edge cases. Run as regression suite before every deployment.

---

## Related Notes

- [[agents|Agents]]
- [[structured-output|Structured Output]]
- [[prompt-engineering|Prompt Engineering]]
- [[react-pattern|ReAct Pattern]]
