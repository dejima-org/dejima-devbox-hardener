#!/usr/bin/env bats
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Brad Anderson
#
# The prose is the product here, so a defect in it is a defect in the
# deliverable rather than a cosmetic problem.
#
# What this catches is the one kind review reliably misses: a paragraph that
# says something correct, twice. A reader skimming for the next instruction
# does not notice the repeat, and a reviewer reading top to bottom takes the
# second copy for a continuation of the first. Section 3 of the node runbook -
# the primary control, and the most-read page here - opened with six duplicated
# lines for long enough to survive two prose passes.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no document repeats a paragraph verbatim" {
    fails=""
    while IFS= read -r f; do
        # Paragraph mode, so a block is compared whole rather than by line: two
        # identical lines are usually a table or a repeated command, and neither
        # is a defect. Short blocks are skipped for the same reason.
        dup=$(awk 'BEGIN{RS=""} length($0)>150 {gsub(/\n/," "); print}' "$REPO/$f" \
              | sort | uniq -d)
        [ -z "$dup" ] || fails="$fails\n  $f: $(printf '%s' "$dup" | cut -c1-70)..."
    done < <(cd "$REPO" && git ls-files '*.md')

    if [ -n "$fails" ]; then
        printf 'paragraphs appearing twice in the same document:%b\n' "$fails" >&2
        false
    fi
}

@test "the guard fails when a paragraph is duplicated, rather than passing quietly" {
    # A checker nobody has watched fail is a checker nobody should trust.
    tmp="$BATS_TEST_TMPDIR/dup.md"
    {
        echo "# Heading"; echo
        for _ in 1 2; do
            echo "This is a paragraph long enough to be worth comparing, which is"
            echo "to say that it runs well past the length threshold the check"
            echo "applies before it looks at a block at all."
            echo
        done
    } > "$tmp"

    dup=$(awk 'BEGIN{RS=""} length($0)>150 {gsub(/\n/," "); print}' "$tmp" | sort | uniq -d)
    [ -n "$dup" ]
}
