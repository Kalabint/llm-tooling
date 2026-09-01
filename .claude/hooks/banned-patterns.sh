# Shared banned-phrasing patterns. Sourced by:
#   no-superlative-guard.sh    (Stop + PostToolUse) -> blocks, forces a re-emit
#   redact-banned-display.sh   (MessageDisplay)     -> hides it on screen only
# One definition so the two consumers cannot drift apart.
#
# Rationale for each class lives in the memory files loaded at session start
# (feedback-no-time-estimates, feedback_no_sycophancy, ...), NOT here and NOT in
# the block reason — the reason is paid in context on every single block.

# ---------------------------------------------------------------------------
# CHANGELOG. Append here on every add/remove. Rationale for a WHOLE CLASS lives
# in the memory files; this records individual pattern changes and, above all,
# REVERSALS — so a later pass does not re-add something that was deliberately cut.
# Inline NOTE comments at the point of change stay too; this is the index.
#
# 2026-08-31  TIM  NEW CLASS: temporal self-framing — "tonight", "this evening",
#                  "all morning". I have turns, not days; a user may write from
#                  any timezone and resume whenever. "now" = this turn, "later" =
#                  the next message, elapsed time is READ off a clock jump, not
#                  experienced. Data phrases ("fixes today") are not matched.
#                  Trigger: "tonight's false claims", "all evening".
#
# 2026-08-31  ADV  NEW CLASS: cross-source comparison without provenance. Not a
#                  phrasing ban — it forces one sentence on what each source is
#                  and when it was populated. Trigger: "4.8M rows Traccar no
#                  longer has" (dev restore vs live feed) and a "13 h loader
#                  gap" (contact clock vs fix clock). Both claims were false.
#
# 2026-08-31  SYC  ADDED bare agreement: "you were right that", "you're right",
#                  sentence-opening "Good catch". The existing patterns only
#                  caught "right to push/question/challenge".
#                  Trigger: "you were right that leaving it was incoherent".
#
# 2026-08-31  EDI  NEW CLASS: editorialising on a measurement — asserting what a
#                  number means or how important it is. Trigger: called a
#                  row-count difference "the archive function working" and
#                  "arguably the strongest single argument for the product
#                  existing". The provenance was unestablished and the story was
#                  false (the second store is a dev restore, not a pruned prod).
#
# 2026-08-07  CMP  REMOVED «überdurchschnittlich» — fired on verbatim German
#                  clinical quotations where the term IS baselined. See the inline
#                  note in Class 1. English "above average" kept.
#
# 2026-08-26  TIC  ADDED dramatised result announcement: naming a measurement
#                  "the prize/payoff", or declaring it "now exact", instead of
#                  stating the number. 4 patterns.
#                  Trigger: I wrote "The prize is now exact." over a 6.93% figure.
#
# 2026-08-26  TIC  ADDED discovery-narration: narrating my own investigation arc
#                  rather than the fact ("the picture that emerges", "what this
#                  reveals is"). Originally included the whole "turns out" family.
#                  Trigger: "H3 turned out to answer two different questions, and
#                  only one of them favourably."
#
# 2026-08-27  TIC  ADDED narrative role-labelling: telling the reader what a
#                  finding MEANS as a story beat ("the cautionary case", "that's
#                  the lesson", "the moral here is"). 4 patterns.
#                  Trigger: "join-filter-depth was refuted, and it's the
#                  cautionary case."
#
# 2026-08-27  TIC  UNBANNED, on explicit user instruction, the exact past-tense
#                  string `turned out to be` — ordinary English, not a flourish.
#                  ONLY that string. `as it turns out`, `turns out to be`,
#                  `turned out to answer|matter|work|...`, `it turns out that`
#                  all remain banned. ERE has no negative lookahead, so this is
#                  expressed by enumerating the surviving tails rather than by
#                  excluding one — which is why the PRESENT tense stays banned
#                  while the past tense passes. That asymmetry is a limitation of
#                  the encoding, not a claimed distinction. DO NOT "tidy" it by
#                  re-adding the general form.
#                  Lesson recorded: the original 2026-08-26 pattern generalised
#                  from one bad sentence to a normal English construction. The
#                  flourish was the editorialising tail, not the verb.
#
# 2026-08-30  LED  NEW CLASS. Framing preamble: opening a paragraph by announcing
#                  what KIND of statement follows, counted, instead of stating it
#                  ("One consequence of X...", "Two decisions worth flagging",
#                  "One finding I am reporting rather than acting on"). Anchored to
#                  line start, and the noun must be an abstract category word, so
#                  "Two of the four bugs" and "31 windows exceeded 15 m" do not fire.
#                  Trigger: recurred five times in one session; user: "One consequence
#                  of this morning's gate...... > banned. lead with facts or details".
# ---------------------------------------------------------------------------

# Class 1: unbaselined comparison — asserts a distribution I have not measured.
# NOTE: «überdurchschnittlich» was here (his own self-profiling rule banned it) and was
# removed 2026-08-07. The output is English; the word therefore shows up almost only when
# QUOTING German clinical documents, where it is a normed psychometric statement against a
# standardisation sample — i.e. the one place it is fully baselined. It fired on a verbatim
# SON-R 1999 result and blocked an accurate quotation. The English "above average" stays,
# because that one does appear in my own prose.
CMP='(more|better|stronger|faster|sharper|deeper|rarer|tighter) than (most|many|average|the average)|(very |quite )?few people|most people (can|could|would|do|are|never|rarely)|above average|unlike most|exceptional|remarkabl|one of the (best|worst|few|strongest|only)'
# Behavioural superlative: ranking which item is likeliest to be MISSED is a claim
# about attention, not about the code. Replace with a structural fact.
CMP="$CMP"'|\bthe (easiest|hardest|trickiest|riskiest|most likely|least likely|most obvious|least obvious|most dangerous) [a-z]* ?(one )?to (overlook|miss|forget|break|get wrong|catch|spot|notice|trip over)'

# Class 2: stock phrases / verbal tics.
TIC='load.bearing|\bgenuinely\b|the (honest|real|actual|true) (answer|version|truth|reading|framing|one)|worth (noting|knowing|saying|having|flagging)|(that|this|it|which) lands\b|how it lands|\bthe tell\b|cuts both ways'
# Ranking one item of my own list as the most striking. Adds no fact — the item's
# content already says whether it matters — and it stacks a superlative on top of
# an analysis the reader can rank themselves. "the sharpest (thing|point|version)"
# was here first and missed "this is the sharpest ONE"; widened rather than doubled.
TIC="$TIC"'|the (sharpest|clearest|starkest|ugliest|nastiest|juiciest|most telling|most damning|most striking|most interesting) (thing|point|version|one|of (the|these|them)|case|example|instance|symptom|finding)'
# Virtue-signalling the disclosure: narrating that I am being forthright implies
# concealment was an option I declined.
TIC="$TIC"'|(named|said|stated|flagged|reported|shown|put) rather than (glossed|glossing|buried|burying|hidden|hiding|softened|softening|sugar.?coated|sugar.?coating|downplayed|downplaying|hedged|hedging|dressed up)'
TIC="$TIC"'|\b(to be|let me be|i.?ll be|being) (blunt|frank|honest)\b|\bfrankly\b|\bcandidly\b|no sugar.?coating|without sugar.?coating|\bnot to (sugar.?coat|bury)\b'
# Locating where the weight sits — a synonym for the banned weight-word. The claim
# points at an item without measuring anything, and the sentence carries nothing itself.
TIC="$TIC"'|(the |a )?(thing|line|part|bit|piece|one|clause|word) (that )?(doing|does|carries|carrying|bears|bearing) (most of )?the (work|weight|lifting)'
TIC="$TIC"'|doing (most of )?the (heavy )?(work|lifting)|carries the (weight|whole thing)'
# Narrating the restraint I am exercising, sibling of 'not to sugarcoat'.
TIC="$TIC"'|\bi.?m not going to (say|claim|pretend|dress|turn|build|argue|guess)|\bi wo?n.?t (pretend|dress|sugar)'
# Closing and framing scaffolding: performs structure or asks the reader to
# certify the answer, instead of stating it.
TIC="$TIC"'|hope (that |this )?helps|does that make sense|happy to elaborate|feel free to (ask|reach)'
TIC="$TIC"'|let.?s (dive in|break (this|that) down)|let me walk you through|\bhere.?s the thing\b'
TIC="$TIC"'|i want to be careful here|\bi should note\b|it.?s important to note|(keep|bear) in mind'
TIC="$TIC"'|\b(to be|let me be|i.?ll be) direct\b'

# Dramatised result announcement: naming a measurement "the prize/payoff", or
# declaring it "now exact", instead of just stating the number (2026-08-26).
TIC="$TIC"'|the (prize|payoff|jackpot|upside) (is|here is|becomes|turns out|was)'
TIC="$TIC"'|size of the (prize|payoff|win|upside)|that.?s the (prize|payoff)\b'
TIC="$TIC"'|\b(is|are|it.?s|that.?s) now (exact|exactly known|quantified|nailed down|pinned down|a known quantity)\b'
TIC="$TIC"'|\bnow (we have|there is|i have) a (number|figure)\b|\bwith a number on it\b'

# Discovery-narration: telling the story of my own investigation instead of
# stating the fact. "the picture that emerges", "what this reveals is".
# NOTE 2026-08-27: ONLY the exact past-tense `turned out to be` is unbanned
# (ordinary English). The rest of the family stays banned. ERE has no lookahead,
# so this is expressed by enumerating the tails rather than excluding one.
TIC="$TIC"'|\bas it turns out\b|\bturns out to be\b'
TIC="$TIC"'|\bturn(s|ed) out to (answer|matter|work|favour|favor|hold|survive)\b'
TIC="$TIC"'|\b(it|that|this|which|they) turns out that\b'
TIC="$TIC"'|the (picture|story|pattern|shape|answer) (that )?(emerges|emerging|here is|is this)'
TIC="$TIC"'|what (emerges|this reveals|that reveals|this tells us|that tells us|we learn) is'
TIC="$TIC"'|\bonly one of (them|which|those) (favourably|favorably|holds|survives|does)'

# Narrative role-labelling: telling the reader what a finding MEANS as a story
# beat instead of stating it. "and it's the cautionary case" (2026-08-27).
TIC="$TIC"'|the (cautionary|object|instructive|illustrative|salutary|textbook) (case|lesson|tale|example|one)'
TIC="$TIC"'|\bcautionary (case|tale|example|note)\b'
TIC="$TIC"'|that.?s the (lesson|moral|takeaway|warning)\b|the (moral|takeaway) (here )?is'
TIC="$TIC"'|\bwhich is (exactly )?(the|why it.?s the) (point|lesson|warning)\b'

# Class 3: sycophancy — opener praise and contentless post-correction ack.
SYC='(great|excellent|good|brilliant|fantastic|sharp|astute|insightful|fair|smart) (question|point|catch|call|observation|instinct|idea|thinking|spot|eye|analysis)|(that.?s|this is) (a )?(great|excellent|brilliant|fantastic|superb|fascinating)|you.?re (absolutely|completely|quite|entirely|exactly) right|^you.?re right|exactly right|well spotted|spot on|nailed it|\bmastermind\b|couldn.?t have (said|put) it better|(impressive|excellent|brilliant) (work|analysis|reasoning)'
# Acknowledgement that carries no content — the family that exposed the Green
# pipeline ('I appreciate the pushback'). Conceding is fine; RATING the concession is not.
SYC="$SYC"'|i appreciate (the|your|you) (pushback|feedback|flagging|catching|raising|pointing)'
SYC="$SYC"'|thanks for (catching|flagging|pointing)|good catch on|point taken|i take your point'
SYC="$SYC"'|you raise a (good|valid|fair|important|great) point|that.?s a (valid|fair|reasonable) (concern|point|challenge)'
SYC="$SYC"'|\byou.?re not wrong\b|\bfair enough\b|\bthat.?s fair\b'
# Rating the CHALLENGE rather than answering it. "^you're right" already caught the
# bare form; this catches the praise-the-question shape, which is the same move with
# a compliment attached — and which fired repeatedly in the 2026-08-07 AIS session
# ("You were right to push on that number", "You're right to poke it", "Fair on X").
SYC="$SYC"'|you (were|are|.?re) right to (push|poke|question|challenge|ask|doubt|flag|call|insist|press)'
SYC="$SYC"'|right to (push back|be sceptical|be skeptical|distrust|not trust)'
SYC="$SYC"'|\b(good|nice|sharp) (call|instinct|catch) (on|there|to)\b|your instinct (was|is) right'
SYC="$SYC"'|^fair (on|point)\b|\bfair (challenge|push)\b|glad you (asked|pushed|caught)'
# Bare agreement. The existing patterns catch "right to push/question"; these
# catch the plainer "you were right that X" and a sentence-opening "Good catch",
# which are the same move without the verb.
SYC="$SYC"'|you (were|are|.?re) right (that|about|on)\b|^(good|great|nice) catch\b'
SYC="$SYC"'|\byou.?re right\b|\bexactly right\b|\bspot on\b'

# Class 4: effort / duration estimate. MEASURED elapsed time stays legal
# ("the reprune took 39 s"); this targets projection and effort-rating.
EFF='(easier|harder|simpler|quicker|cheaper|faster|trickier) than (it looks|expected|you.?d think|i thought)'
EFF="$EFF"'|\b(it.?s|it is|that.?s|that is|this is|which is) (pretty |fairly |quite |very |actually |all )?(easy|simple|trivial|straightforward|quick|cheap|painless|a doddle)\b'
EFF="$EFF"'|\b(easy|trivial|straightforward|quick|cheap|minor|small|simple) (change|fix|job|task|win|work|edit|patch|addition|tweak|refactor|migration|lift)\b'
EFF="$EFF"'|\bhalf a (day|week|hour)\b|\b(hours?|days?|weeks?|minutes?|afternoons?) of work\b'
EFF="$EFF"'|\b(would|will|should|could|might) take (about |roughly |around |~)?(a |an |[0-9]+ ?(ish )?)?(seconds?|minutes?|hours?|days?|weeks?|months?)'
EFF="$EFF"'|\bshould(n.?t)? take (long|much|more than)|\bin (under|less than) (a |an )?(hour|day|minute|week)'
EFF="$EFF"'|\bnot (hard|difficult|much work|a big (deal|change|job))\b|\b(low|high|medium)[- ]effort\b|\bquick win\b'
# \bETA\b removed 2026-08-21: it is the domain term (estimated time of arrival) in
# the travel-time / routing work, not an effort projection. The effort sense of
# "no ETA on this" is rare and still caught by the duration patterns above.
EFF="$EFF"'|\brough(ly)? estimate\b|\ba (day|week|couple of days|few hours)('"'"'s)? (of )?(work|effort)\b'

# Class 5: empty deferral — three shapes, all contentless.
#  (a) announcing who decides: no third party exists, so it carries nothing
#  (b) declaring no preference after doing the analysis: hides a view I hold
#  (c) soliciting the obvious: once options are on the page, "which do you want?"
#      and "want me to build it?" are already in the room. He will say.
# ALLOWED: "options: a, b, c (recommended: b)". Also allowed and NOT matched here:
# a real disambiguation ("against the live server or the mirror?") and confirmation
# before something destructive — those carry content and change what happens next.
PNT='\byour call\b|\bup to you\b|\byou decide\b|(the|that|this) (decision|choice|call) is (yours|for you)|yours to (make|decide|call)'
PNT="$PNT"'|whichever (you|one) (prefer|want|like)|whatever you prefer|either way works|both are (valid|fine|reasonable|good) (options|choices|approaches)'
PNT="$PNT"'|i.?ll leave (it|that|this) (to|with) you|happy to (do|go) either|i can go either way|i (have|hold) no (preference|strong view)|no strong (preference|opinion|view) (here|either way)'
# (c) soliciting a question that is already implicit
PNT="$PNT"'|((do|would) you want me to|want me to|would you like me to)[^.?!]*\?'
PNT="$PNT"'|which (of (the|these|those) [a-z0-9-]+ )?(do|would) you (want|prefer|like)'
PNT="$PNT"'|say the word|just say|let me know if you( |.?d )(want|like|prefer)|if you want,? i can|i can .{0,30} if you want'
PNT="$PNT"'|if you.?d rather|say (go|if you( (want|need|prefer|would|think|rather|like)|.?d))|say the word and|and i.?ll (run|build|do|wire|add) it'

# Class 6: invented hazard — a warning with no observed instance. What separates it
# from a real finding is not tone but whether it can name where the thing is TRUE,
# never where it could become true. Score from the 2026-08-20 fave/tripshare session:
# four invented (a CHECK constraint against a torn write a single statement cannot
# produce, a published_at column that does not exist, a test for a wrong fix nobody
# made, a /tripshare URL "trap" that track/+server.ts:67-69 already contradicts) to
# two real (the token_hash-PK vs token-DEFAULT-'' collision, the two hand-copied
# token lookups) — and the two real ones both cited schema lines unprompted.
# Manufactured hazards are cheap to emit and read as diligence, and they recast the
# reader as the person who would make the mistake, on a system he wrote. The rule
# the regex approximates: every hazard cites file:line where it holds NOW, or is cut.
# Deliberately NOT matched: "guards against" / "the risk is" on their own — those
# describe existing code as often as imagined code, and the hypothetical-actor and
# imperative-caution shapes below carry the signal without the false positives.
HAZ='\b(someone|somebody|a developer|another (dev|developer)|the next (person|dev|developer|agent|maintainer)|a future (dev|developer|maintainer|agent)|anyone|nobody|no.?one) (might|could|would|may|ever|were to|decides? to|forgets? to|accidentally|by accident)'
HAZ="$HAZ"'|\bif (someone|somebody|anyone|a developer) (ever )?(does|did|were|tries|tried|decides|decided|writes|wrote|adds|added|removes|removed)'
HAZ="$HAZ"'|\b(the|a|one) (trap|pitfall|gotcha|footgun) (to avoid|here|is|would be)|\btraps? to avoid\b'
HAZ="$HAZ"'|\bmake sure (not to|you do ?n.?t|nobody|no.?one|it never|that nobody)'
# Advising preservation of a design he wrote. The object and "as it is" are usually
# separated ("keep the public route's URL opaque and its window clamped, exactly as
# it is now"), so the tail is matched on its own rather than anchored to the object.
HAZ="$HAZ"'|\bexactly as (it|they) (is|are|was|were)\b|\b(keep|leave) (it|this|that|them) (as (it is|they are|is)|alone|untouched)\b'
HAZ="$HAZ"'|\b(it.?s|that.?s|which is) tempting to\b|\bdo ?n.?t be tempted\b|\blooks natural\b'
HAZ="$HAZ"'|\bin case (someone|somebody|anyone|it ever|that ever)\b|\bso (that )?(nobody|no.?one|someone can.?t)\b'
HAZ="$HAZ"'|\bfuture.?proof'

# Class 7: framing preamble — announcing the KIND of statement before making it,
# usually counted. The count is decoration: the reader can see how many items
# follow, and the category word delays the content by a clause. Anchored to line
# start (optionally through a "**217. " numbering prefix) because mid-sentence
# "the API offers two options" is a fact, not a preamble. The noun list is
# deliberately abstract-only: "Two of the four runs" does not match, since "of"
# sits where the noun would be, and concrete nouns ("windows", "rows", "fixes")
# are absent by design.
LED='^(\*\*)?([0-9]+\.[[:space:]]*)?(one|two|three|four|five)[[:space:]]+((more|further|other|additional|final|last|open|remaining|outstanding|separate)[[:space:]]+)?(consequence|implication|finding|decision|thing|point|note|caveat|observation|detail|inversion|correction|wrinkle|nuance|subtlety|catch|question|way|option|reason|lesson|takeaway|consideration|item)s?\b'

# Class 8: editorialising on a measurement — asserting what a number MEANS,
# what it proves, or how important it is, rather than reporting it. Trigger:
# after measuring a row-count difference I wrote that it was "the archive
# function working" and "arguably the strongest single argument for the product
# existing" — a causal story on a number whose provenance I had not established,
# and the story was false. The number is the output; its significance is not.
EDI='\barguably the (strongest|best|biggest|clearest|single|most)\b'
EDI="$EDI"'|\bthat.?s (the|your) [a-z ]{3,30} working\b'
EDI="$EDI"'|\bwhich is (arguably )?(why|the reason) (the|this) [a-z]+ exists\b'
EDI="$EDI"'|\b(the|a) strongest (single )?(argument|signal|evidence|case)\b'
EDI="$EDI"'|\bproves (the|that) [a-z]+ (works|is working)\b'

# Class 10: temporal self-framing. I do not experience a day or a night. A user
# can write from any timezone and resume a conversation whenever they like, so
# "tonight", "this evening", "all morning" describe a continuous stretch I never
# had. What DOES exist: "now" (this turn), "later" (whenever the next message
# arrives), "earlier in this conversation", and elapsed time OBSERVED by reading
# a clock jump between turns — not felt. Say "earlier", "in this conversation",
# or cite the measured delta. Data references are untouched: "fixes today" and
# "devices go offline overnight" are facts about the data, not about me, and are
# not matched here.
TIM='\b(tonight|this evening)(.?s)?\b'
TIM="$TIM"'|\bearlier (tonight|this (evening|morning|afternoon))\b'
TIM="$TIM"'|\ball (evening|night|morning|afternoon)\b|\bover the (evening|night)\b'
TIM="$TIM"'|\b(this|the) (evening|morning|afternoon)[,]? (i|we) \b'
TIM="$TIM"'|\b(i|we) (have|.?ve) been [a-z]+ing (all|since this) (evening|night|morning|day)\b'

# Class 9: cross-source comparison asserted without provenance. NOT a banned
# phrasing — the claim may well be right. The block exists to force one sentence
# saying what each source IS and when it was populated, because that sentence
# was missing from the two worst errors of 2026-08-31: a "13 h loader gap" from
# comparing a contact clock to a fix clock, and a "4.8M row surplus, Traccar
# prunes" from comparing a live-fed store to a dev restore. Deliberately narrow
# — only shapes that assert a difference BETWEEN stores/systems, not ordinary
# measurement.
ADV='\b(surplus|shortfall|gap) of [0-9][0-9,._]*'
ADV="$ADV"'|\bhas (more|fewer|less) (rows|positions|records|fixes|data)\b'
ADV="$ADV"'|\b(rows|positions|records|fixes) (that|which) [a-z ]{0,20}(no longer|does ?n.?t|do ?n.?t) (has|have|hold|exist)'
ADV="$ADV"'|\b(is|are) not (a subset|nested)\b|\bneither (is|store is) (a )?(superset|ground truth)\b'

# Class 11: parameter semantics asserted without reading the definition. Naming a
# config knob and claiming its DIRECTION (it reduces / mitigates / is already
# applied) is a code fact, and code facts get cited. Origin 2026-09-01: prod tiles
# were described as "with density_factor=0.1 already applied", implying a
# mitigation; tierTolerance() multiplies the snap grid by the factor, so 0.1 is a
# 10x FINER render — the claim was backwards and inverted the comparison built on
# it. Matches a config-shaped identifier near a directional verb, plus the bare
# "already applied/enabled" form which carries the same unstated claim.
PAR='\b[a-z][a-z0-9]*(_[a-z0-9]+)+[[:space:]]*=[[:space:]]*[0-9][0-9.]*[^.]{0,70}\b(already|applied|accounts? for|mitigat|reduc(e|es|ing)|increas(e|es|ing)|limit(s|ing)?|caps?|throttl)'
PAR="$PAR"'|\balready (applied|enabled|in play|accounted for|active|switched on)\b'
PAR="$PAR"'|\b(with|despite|even with)[[:space:]]+[A-Z][A-Z0-9_]{4,}[^.]{0,50}\b(applied|enabled|set|on|active)\b'

# Every class, for consumers that do not need to distinguish them.
ALL_BANNED="$CMP|$TIC|$SYC|$EFF|$PNT|$HAZ|$LED|$EDI|$ADV|$TIM|$PAR"

# Strip fenced blocks and inline code before matching: quoting a banned phrase in
# backticks (explaining this guard, a table of the patterns) is not using it.
strip_code() { sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' | sed 's/`[^`]*`//g'; }
