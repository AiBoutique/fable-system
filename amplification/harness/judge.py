"""LLM-lenient fallback judge -- the model-calling half of the ``llm_judge`` grader.

Motivation (research 2026-07-16, arXiv:2606.24839): deterministic parsers are
lossy on free-form answers -- a last-number heuristic recovered 26% of ground
truths, a keyword-anchored parser 86%, and an LLM-lenient grader 97%. So the
harness keeps CODE graders as the fast, cheat-resistant DEFAULT and adds an
LLM-lenient judge ONLY as a fallback: it is consulted when a code grader FAILS a
cell, to recover keyword-vocabulary false negatives (a correct answer the code
grader missed on phrasing). It never overrides a code-grader PASS.

Discipline (README section 3), enforced here:
  * DIFFERENT model than the one under test (never self-grade) -- the runner
    passes ``judge_model`` and refuses ``judge_model == model_under_test``;
  * BLIND -- the judge sees only the task question, the reference answer, and the
    candidate text, never which condition/model produced it;
  * ORDINAL -- a fixed 0..4 rubric parsed deterministically by ``graders.llm_judge``;
  * budget-spending and OFF by default (``run.py --judge-fallback``).

``graders.llm_judge`` (pure) parses the judge's text; nothing here scores.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import adapters  # noqa: E402

# A fixed, blind, ordinal rubric. The reference answer comes from the task's
# ``notes`` or an explicit ``judge_reference`` field, NOT from the grader (which
# may be exactly what mis-scored the answer).
JUDGE_TEMPLATE = """\
You are a strict but fair grader. Decide whether the CANDIDATE ANSWER correctly \
answers the QUESTION, judged against the REFERENCE. Ignore formatting, phrasing, \
extra explanation, and order of words -- grade only whether the substantive \
answer is correct. Do not be swayed by confident tone.

QUESTION:
{question}

REFERENCE (the correct answer / key facts):
{reference}

CANDIDATE ANSWER:
{candidate}

Reply with exactly two lines and nothing else:
SCORE: <an integer 0-4, where 0=completely wrong, 4=fully correct>
VERDICT: <CORRECT or INCORRECT>
"""


def build_prompt(question, reference, candidate):
    """The blind rubric prompt (no condition/model identity ever included)."""
    return JUDGE_TEMPLATE.format(question=str(question).strip(),
                                 reference=str(reference).strip(),
                                 candidate=str(candidate).strip())


def run_judge(task, candidate_output, judge_model, model_under_test,
              adapter_spec=None, dry_run=True):
    """Call the DIFFERENT judge model on one failed cell; return its raw text.

    Refuses to self-grade. The reference is the task's ``judge_reference`` if
    present, else its ``notes`` (author's reference answer). Returns ``None`` if
    the judge itself errors (the runner then keeps the original code grade).
    """
    if judge_model == model_under_test:
        raise ValueError(
            f"judge model must DIFFER from the model under test "
            f"({model_under_test!r}); never self-grade (README section 3).")
    reference = task.get("judge_reference") or task.get("notes") or ""
    if not reference:
        return None  # nothing to judge against -> keep the code grade
    prompt = build_prompt(task["prompt"], reference, candidate_output)
    spec = dict(adapter_spec or {"name": "claude_cli"})
    spec["model"] = judge_model
    spec["dry_run"] = dry_run
    # BLIND: system_core=None -> the judge gets no discipline core and no identity
    r = adapters.run(spec, None, prompt)
    if r["meta"].get("returncode") not in (0, None):
        return None
    return r["output"]
