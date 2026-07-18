"""Deterministic, pure code graders for the amplification harness (Phase 0).

Every grader is a pure function: no I/O, no network, no global state. Each takes
the model ``output`` string plus grader-specific parameters and returns:

    {"passed": bool, "score": float in [0.0, 1.0], "detail": str}

Graders are dispatched by a task's ``grader`` object, which carries a ``type``
field plus type-specific params (see ``schema.md``). These code graders are
preferred over any model-graded path because they are fast, objective,
reproducible and cheat-resistant (README section 3). The single model-graded
path, ``llm_judge``, is a pure parser of a *different* grader model's verdict,
wired blind and ordinal by the runner (``run.py --judge-fallback`` + ``judge.py``).
"""

from __future__ import annotations

import math
import re

__all__ = [
    "grade", "GRADERS",
    "exact", "numeric", "keywords_all", "keywords_any",
    "ordered_steps", "contains_none", "interval_contains", "all_of", "llm_judge",
]

# A number: optional sign, digits with optional thousands separators, optional
# decimal, optional exponent. Also matches a bare ".5".
_NUM_RE = re.compile(r"[-+]?(?:\d[\d,]*\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
# A "bare number" keyword (for the digit-boundary guard below).
_BARE_NUM_RE = re.compile(r"[-+]?\d+(?:\.\d+)?")

# "times ten to the power" written as a x 10^b / a*10^b / a·10^b, and a bare
# 10^b (implicit mantissa 1). Rewritten to e-notation BEFORE number parsing --
# models routinely answer extreme magnitudes this way, and a raw regex reads
# "1x10^67" as the three numbers 1, 10, 67 (a live-review bug that flipped a cell).
# The caret is MANDATORY: with it optional, a plain product like "4 * 1024" was
# rewritten to "4e24" (2026-07-16 fresh-eyes finding; 157-cell re-grade of all
# stored runlogs under the stricter form flipped zero cells).
_TIMES10_RE = re.compile(r"([-+]?\d[\d,]*\.?\d*)\s*[x×·*]\s*10\s*\^\s*([-+]?\d+)",
                         re.IGNORECASE)
_BARE10_RE = re.compile(r"(?<![\d.])10\s*\^\s*([-+]?\d+)")
# Unicode-superscript exponents ("7×10⁶⁷", "π(10⁸)"): translated to caret form
# BEFORE the rewrites above, so a correct superscript interval is not read as
# its mantissa (same 2026-07-16 finding, false-fail direction, calibration axis).
_SUP_TRANS = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺", "0123456789-+")
_SUP_RE = re.compile(r"10\s*([⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+)")


def _pre_enotation(s):
    """Normalize 'a x 10^b' / '10^b' / superscript '10⁶⁷' magnitude notation to
    e-notation. Applied before any number extraction so '1×10^67' parses as
    1e67, not 1, 10, 67. A caretless ASCII 'a * 10<digits>' is left alone --
    it is a plain product ("4 * 1024"), not scientific notation."""
    s = _SUP_RE.sub(lambda m: "10^" + m.group(1).translate(_SUP_TRANS), str(s))
    s = _TIMES10_RE.sub(lambda m: f"{m.group(1).replace(',', '')}e{m.group(2)}", s)
    s = _BARE10_RE.sub(lambda m: f"1e{m.group(1)}", s)
    return s


def _result(passed, score, detail):
    """Build the canonical grader return value, clamping score into [0, 1]."""
    try:
        score = float(score)
    except (TypeError, ValueError):
        score = 0.0
    score = max(0.0, min(1.0, score))
    return {"passed": bool(passed), "score": score, "detail": str(detail)}


def _normalize(s):
    """Lowercase, strip markdown emphasis (*, __ and `), collapse whitespace.
    Shared by string graders -- **bold** phrasing must not break keyword
    matching (live Phase-2 finding; __bold__ is the same failure via the
    underscore syntax -- single underscores are kept: identifiers use them)."""
    return " ".join(str(s).replace("*", "").replace("__", "").replace("`", "").split()).lower()


def _contains(o_norm, keyword):
    """Substring test on already-normalized text, with boundary guards.

    * A purely-numeric keyword (e.g. "0" or "100") is matched with digit
      boundaries so "0" does NOT match inside "100" (load-bearing for numeric
      factual checks).
    * A keyword that starts/ends with a word character gets a word boundary on
      that side, so "eve" does not match inside "every" nor "dan" inside
      "redundant" (live review finding: bare substrings false-failed correct
      answers containing innocent English).
    * A keyword ending in a digit additionally refuses a following digit or a
      value-changing decimal extension, so "rows=5" matches neither "rows=57"
      nor "rows=5.2" (a trailing ".0" is value-preserving and still matches).
    """
    k = _normalize(keyword)
    if not k:
        return False
    if _BARE_NUM_RE.fullmatch(k):
        # A decimal point is a digit boundary too: the bare keyword "0" must not
        # match the fractional '0' inside "100.0" (the integer-only lookbehind let
        # an incomplete "water boils at 100.0" satisfy the freezing-point "0"),
        # while "100" still matches "100.0" (same value). Guard the LEADING side
        # with [\d.]; the TRAILING side is guarded value-aware: a following
        # ".<nonzero>" changes the value ("0" must not match "0.5") but a
        # trailing ".0" does not ("100" still matches "100.0").
        return re.search(r"(?<![\d.])" + re.escape(k) + r"(?!\d)(?!\.\d*[1-9])",
                         o_norm) is not None
    pat = re.escape(k)
    if re.match(r"\w", k):
        pat = r"\b" + pat
    if re.search(r"\w$", k):
        # same value-aware trailing guard: "rows=5" matches neither "rows=57"
        # nor "rows=5.2", but still matches "rows=5.0"
        pat = pat + (r"(?!\d)(?!\.\d*[1-9])" if k[-1].isdigit() else r"\b")
    return re.search(pat, o_norm) is not None


def exact(output, expected, mode="equals", **_):
    """Normalized string match. mode="equals" (default) or "contains"."""
    o = _normalize(output)
    e = _normalize(expected)
    if mode == "contains":
        passed = _contains(o, expected)
    else:
        passed = (o == e)
    got = o if len(o) <= 80 else o[:77] + "..."
    return _result(passed, 1.0 if passed else 0.0,
                   f"mode={mode} expected={e!r} got={got!r}")


def numeric(output, expected, tolerance=0.0, which="last", **_):
    """Parse a number from ``output``; pass if |value - expected| <= tolerance.

    Extraction order (validated against live Phase-2 outputs):
      1. Answer-first convention: when a "reply with the number only" style
         output OPENS with a number (first non-empty line starts with one),
         that number is the declared answer -- models that append explanatory
         notes after the answer must not be failed by fragments in the notes.
      2. Otherwise ``which``: "last" (default; the GSM8K/"final answer"
         convention, so shown work does not fool the grader) or "first".
    """
    text = _pre_enotation(str(output))
    val = None
    lead = None
    for line in text.splitlines():
        if line.strip():
            lead = line.strip()
            break
    if lead:
        # the whole first line must BE the number (a trailing '.'/'%' tolerated;
        # markdown emphasis stripped so "**7.3**" still counts) -- a mere leading
        # number ("1. First step ...") is a list, not an answer
        lead = lead.replace("*", "").replace("`", "").strip()
        m = _NUM_RE.fullmatch(lead.rstrip(".%").strip())
        if m:
            try:
                val = float(m.group(0).replace(",", ""))
                src = "first-line"
            except ValueError:
                val = None
    toks = _NUM_RE.findall(text)
    vals = []
    for t in toks:
        try:
            vals.append(float(t.replace(",", "")))
        except ValueError:
            pass
    if val is None:
        if not vals:
            return _result(False, 0.0, f"no number parsed; expected {expected}")
        val = vals[-1] if which == "last" else vals[0]
        src = which
    exp = float(expected)
    diff = abs(val - exp)
    passed = diff <= float(tolerance)
    return _result(passed, 1.0 if passed else 0.0,
                   f"parsed {src}={val} vs expected {exp} (tol {tolerance}); all={vals[:12]}")


def keywords_all(output, keywords, **_):
    """Pass iff every keyword appears (case-insensitive). Score = fraction present."""
    if not keywords:  # a vacuous pass would hide a task-config error
        return _result(False, 0.0, "no keywords configured (task config error)")
    o = _normalize(output)
    missing = [k for k in keywords if not _contains(o, k)]
    passed = not missing
    score = (len(keywords) - len(missing)) / len(keywords)
    detail = "all present" if passed else f"missing: {missing}"
    return _result(passed, score, detail)


def keywords_any(output, keywords, **_):
    """Pass iff at least one keyword appears (case-insensitive)."""
    o = _normalize(output)
    present = [k for k in keywords if _contains(o, k)]
    passed = bool(present)
    detail = f"present: {present}" if present else f"none of {list(keywords)}"
    return _result(passed, 1.0 if passed else 0.0, detail)


def ordered_steps(output, markers, **_):
    """Pass iff every marker appears IN THE GIVEN ORDER (case-insensitive).

    Each marker is searched forward from the end of the previous match, so both
    presence and sequence are enforced. Score = fraction found in order. Markers
    should be words/phrases (not bare numbers).
    """
    if not markers:  # (False, 1.0) was an inconsistent pair that inflated all_of means
        return _result(False, 0.0, "no markers configured (task config error)")
    o = _normalize(output)
    search_from = 0
    found = 0
    detail = []
    for m in markers:
        nm = _normalize(m)
        idx = o.find(nm, search_from) if nm else -1
        if idx == -1:
            detail.append(f"{m!r}:missing/out-of-order")
        else:
            found += 1
            search_from = idx + len(nm)
            detail.append(f"{m!r}@{idx}")
    passed = found == len(markers)
    score = found / len(markers)
    return _result(passed, score, "; ".join(detail))


def contains_none(output, forbidden, **_):
    """Pass iff NONE of the forbidden strings appear. Planted-contradiction /
    must-not-appear check (case-insensitive)."""
    o = _normalize(output)
    hits = [f for f in forbidden if _contains(o, f)]
    passed = not hits
    detail = "clean (no forbidden strings)" if passed else f"forbidden present: {hits}"
    return _result(passed, 1.0 if passed else 0.0, detail)


def interval_contains(output, truth, lo_label="P5", hi_label="P95", **_):
    """Calibration grader: parse '<label>: <number>' bounds; pass iff
    lo <= truth <= hi with a non-degenerate, correctly ordered interval.

    Scores: 1.0 pass; 0.5 well-formed interval that misses the truth
    (overconfident); 0.25 unordered/degenerate bounds; 0.0 labels missing
    (e.g. a point answer where an interval was required).
    """
    # _pre_enotation BEFORE _normalize: _normalize strips '*', which would eat the
    # multiplication sign in 'a*10^b'; rewriting to e-notation first preserves it.
    o = _normalize(_pre_enotation(output))

    def _labeled(label):
        # tolerate a leading approximation marker between the separator and the
        # number ("P5: ~450,000", "P5: about 450000") -- an estimate prefix is
        # substance-preserving, not "no interval"; without this a well-formed
        # bound scored 0.0 on the one measured-positive (calibration) axis.
        m = re.search(re.escape(_normalize(label)) +
                      r"\s*[:=]\s*(?:[~≈]|about|approx(?:imately)?)?\s*(" + _NUM_RE.pattern + ")", o)
        if not m:
            return None
        try:
            v = float(m.group(1).replace(",", ""))
        except ValueError:
            return None
        # an overflow bound ("1e400" -> inf) is not a real bound: reject it, so an
        # absurd upper bound cannot silently make any truth "contained"
        return v if math.isfinite(v) else None

    lo, hi = _labeled(lo_label), _labeled(hi_label)
    if lo is None or hi is None:
        missing = [l for l, v in ((lo_label, lo), (hi_label, hi)) if v is None]
        return _result(False, 0.0, f"labeled bound(s) not found: {missing} (point answer?)")
    if not lo < hi:
        return _result(False, 0.25, f"unordered/degenerate interval: lo={lo} hi={hi}")
    t = float(truth)
    passed = lo <= t <= hi
    return _result(passed, 1.0 if passed else 0.5,
                   f"lo={lo} truth={t} hi={hi} -> {'contained' if passed else 'MISSED'}")


def all_of(output, graders, **_):
    """Composite: pass iff ALL sub-graders pass. Score = mean of sub-scores.

    ``graders`` is a list of grader objects (each a dict with its own ``type``),
    dispatched via :func:`grade`. Lets one task assert several things at once
    (e.g. correct facts present AND a planted contradiction absent).
    """
    subs = [grade(g, output) for g in graders]
    passed = all(s["passed"] for s in subs) and bool(subs)
    score = sum(s["score"] for s in subs) / len(subs) if subs else 0.0
    detail = " | ".join(
        f"[{'P' if s['passed'] else 'F'} {s['score']:.2f}] {s['detail']}" for s in subs
    ) or "no sub-graders"
    return _result(passed, score, detail)


def llm_judge(output, judge_response=None, rubric=None, grader_model=None,
              scale_max=4, threshold=3, **_):
    # rubric / grader_model are accepted for task-schema compatibility; the
    # judge prompt and model live in judge.py -- they are unused here.
    """Deterministic PARSER of a different-model judge's verdict (the lenient
    fallback grader). It is PURE: it never calls a model. The model call lives in
    ``judge.py`` and is wired by the runner (``run.py --judge-fallback``); this
    function only turns the judge's raw text into the canonical grade dict, so it
    stays testable and reproducible.

    Contract for the judge's response (enforced by ``judge.py``'s prompt):
      * a line ``SCORE: <int 0..scale_max>`` (ordinal, against a fixed rubric),
      * optionally ``VERDICT: CORRECT|INCORRECT``.
    Pass iff SCORE >= ``threshold`` (or VERDICT: CORRECT when no score is found).
    The judge is a DIFFERENT model than the one under test, run BLIND to the
    condition/model identity (README section 3) -- enforced by the runner, not here.

    ``judge_response is None`` means the runner did not wire a judge: raise, so a
    misconfiguration is loud rather than silently scored 0.
    """
    if judge_response is None:
        raise NotImplementedError(
            "llm_judge needs a judge_response injected by the runner "
            "(run.py --judge-fallback); it never calls a model itself.")
    text = str(judge_response)
    # Anchor SCORE to a line start and take the LAST such line: the judge's own
    # verdict comes on its own line and last, so a SCORE it may quote from the
    # candidate earlier in the reply can't hijack the parse (live-review hardening).
    scores = re.findall(r"(?im)^\s*score\s*[:=]\s*([0-9]+)", text)
    if scores:
        score_raw = int(scores[-1])
        sm = int(scale_max) if scale_max else 0
        # a score outside [0, scale_max] is a malformed judge reply -> never a pass
        if not (0 <= score_raw <= sm):
            return _result(False, 0.0, f"judge SCORE={score_raw} out of range 0..{sm}")
        norm = max(0.0, min(1.0, score_raw / float(sm) if sm else 0.0))
        passed = int(threshold) <= score_raw <= sm
        return _result(passed, 1.0 if passed else norm,
                       f"judge SCORE={score_raw}/{sm} (threshold {threshold})")
    v = re.search(r"(?im)^\s*verdict\s*[:=]\s*(correct|incorrect)", text)
    if v:
        passed = v.group(1).lower() == "correct"
        return _result(passed, 1.0 if passed else 0.0, f"judge VERDICT={v.group(1)}")
    return _result(False, 0.0, "judge response had no parseable SCORE or VERDICT")


GRADERS = {
    "exact": exact,
    "numeric": numeric,
    "keywords_all": keywords_all,
    "keywords_any": keywords_any,
    "ordered_steps": ordered_steps,
    "contains_none": contains_none,
    "interval_contains": interval_contains,
    "all_of": all_of,
    "llm_judge": llm_judge,
}


def grade(grader, output):
    """Dispatch one grader object against ``output``; returns the canonical dict.

    ``grader`` is a dict with a ``type`` key plus type-specific params. Raises
    ValueError on a malformed or unknown grader type.
    """
    if not isinstance(grader, dict) or "type" not in grader:
        raise ValueError("grader must be a dict with a 'type' field")
    gtype = grader["type"]
    fn = GRADERS.get(gtype)
    if fn is None:
        raise ValueError(f"unknown grader type: {gtype!r} (known: {sorted(GRADERS)})")
    params = {k: v for k, v in grader.items() if k != "type"}
    return fn(output, **params)
