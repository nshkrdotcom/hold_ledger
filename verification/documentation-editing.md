# Editing the review guides

`guides/human_review.md` serves per-change review; `guides/audit.md` serves initial or periodic system assurance. Both are written for an engineer deciding what evidence to trust. Its job
is to help that engineer inspect and approve a concrete claim. Keep the editing
procedure here so authoring notes do not distract from the published review.

## Sources and decisions

- [Diátaxis: How-to guides](https://diataxis.fr/how-to-guides/) grounds a guide in
  the reader's task. Keep the checklist actionable; link to the crash course for
  instruction in Lean instead of repeating it.
- [Jonathan Shewchuk: Three Sins of Authors in Computer Science and Math](https://www.cs.cmu.edu/~jrs/sins.html)
  identifies empty introductions and prose that merely repeats a contents list.
  Start with the review decision and remove ceremonial transitions.
- [Google: Self-editing](https://developers.google.com/tech-writing/two/editing)
  offers checks for audience, active voice and phrasing read aloud. Apply these
  one section at a time, with a separate accuracy pass after prose edits.
- [Write the Docs: How to write software documentation](https://www.writethedocs.org/guide/writing/beginners-guide-to-docs/)
  emphasizes audience needs and direct access to examples/source. Keep source
  links beside the assessment and explain why each finding matters.

## Procedure

1. Check scope and order. In human_review.md, keep one tier/action table and one review checklist, a conservative proof-body classification procedure, independent traces and hidden exercise answers. In audit.md, keep policy and source assessment. Use verification/review-policy.json for paths; do not duplicate an authoritative path list.
2. For each section, mark the decision, source and consequence of each paragraph.
   Delete paragraphs that provide none of these. Keep necessary qualifications
   about proof domains, evidence and assumptions.
3. Replace abstract constructions with an actor and a verb. Replace praise,
   canned transitions, rhetorical contrasts, redundant summaries and inflated
   vocabulary. Do not replace precise technical terms just to vary the wording.
4. Inspect sentence rhythm. Split sentences carrying unrelated claims; join
   choppy fragments that belong together. Avoid making every paragraph the same
   length or turning every explanation into a three-item list.
5. Apply small replacements to one section at a time and inspect each diff.
   Read every resulting paragraph for awkward phrasing. A banned-word scan can
   prompt inspection, but cannot certify natural prose or identify authorship.
6. Recheck the revised claim against source. Preserve words such as "finite",
   "valid", "local" and "assumed" when removing them would strengthen a claim.
   Distinguish code inspection, machine checks and human approval.
7. Inspect the complete rendered guide, README entry point, HexDocs navigation,
   local links and package contents. Run documentation checks for prose changes. Changes to review-policy tooling, CI or agent instructions also require tooling tests and the formal gate specified by repository policy.

Finish only after every section has received the prose and source checks. Keep
the qualifications that make a claim accurate, even when they take another
sentence to explain.
