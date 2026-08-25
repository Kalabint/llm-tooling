# Shared banned-phrasing patterns. Sourced by no-superlative-guard.sh, which
# blocks a turn containing any match and forces a silent re-emit.
#
# Six classes, each a habit that adds no information:
#   CMP  unbaselined comparison   - asserts a distribution never measured
#   TIC  stock phrase / verbal tic - scaffolding that carries no fact
#   SYC  sycophancy               - opener praise, contentless correction-ack
#   EFF  effort / duration guess  - projected time or effort rating (measured elapsed is fine)
#   PNT  empty deferral           - "your call" / "want me to?" after the analysis is done
#   HAZ  invented hazard          - a warning that cannot name where it is TRUE now
#
# The regexes are deliberately broad; tune them to your own habits. strip_code
# removes fenced and inline code first, so quoting a banned phrase in backticks
# (e.g. documenting the rule) does not trip the guard.

CMP='(more|better|stronger|faster|sharper|deeper|rarer|tighter) than (most|many|average|the average)|(very |quite )?few people|most people (can|could|would|do|are|never|rarely)|above average|unlike most|exceptional|remarkabl|one of the (best|worst|few|strongest|only)'
CMP="$CMP"'|\bthe (easiest|hardest|trickiest|riskiest|most likely|least likely|most obvious|least obvious|most dangerous) [a-z]* ?(one )?to (overlook|miss|forget|break|get wrong|catch|spot|notice|trip over)'

TIC='load.bearing|\bgenuinely\b|the honest (answer|version|truth|reading|framing|one)|worth (noting|knowing|saying|having|flagging)|(that|this|it|which) lands\b|how it lands|\bthe tell\b|cuts both ways'
TIC="$TIC"'|the (sharpest|clearest|starkest|ugliest|nastiest|juiciest|most telling|most damning|most striking|most interesting) (thing|point|version|one|of (the|these|them)|case|example|instance|symptom|finding)'
TIC="$TIC"'|(named|said|stated|flagged|reported|shown|put) rather than (glossed|glossing|buried|burying|hidden|hiding|softened|softening|sugar.?coated|sugar.?coating|downplayed|downplaying|hedged|hedging|dressed up)'
TIC="$TIC"'|\b(to be|let me be|i.?ll be|being) (blunt|frank|honest)\b|\bfrankly\b|\bcandidly\b|no sugar.?coating|without sugar.?coating|\bnot to (sugar.?coat|bury)\b'
TIC="$TIC"'|(the |a )?(thing|line|part|bit|piece|one|clause|word) (that )?(doing|does|carries|carrying|bears|bearing) (most of )?the (work|weight|lifting)'
TIC="$TIC"'|doing (most of )?the (heavy )?(work|lifting)|carries the (weight|whole thing)'
TIC="$TIC"'|\bi.?m not going to (say|claim|pretend|dress|turn|build|argue|guess)|\bi wo?n.?t (pretend|dress|sugar)'
TIC="$TIC"'|hope (that |this )?helps|does that make sense|happy to elaborate|feel free to (ask|reach)'
TIC="$TIC"'|let.?s (dive in|break (this|that) down)|let me walk you through|\bhere.?s the thing\b'
TIC="$TIC"'|i want to be careful here|\bi should note\b|it.?s important to note|(keep|bear) in mind'
TIC="$TIC"'|\b(to be|let me be|i.?ll be) direct\b'

SYC='(great|excellent|good|brilliant|fantastic|sharp|astute|insightful|fair|smart) (question|point|catch|call|observation|instinct|idea|thinking|spot|eye|analysis)|(that.?s|this is) (a )?(great|excellent|brilliant|fantastic|superb|fascinating)|you.?re (absolutely|completely|quite|entirely|exactly) right|^you.?re right|exactly right|well spotted|spot on|nailed it|\bmastermind\b|couldn.?t have (said|put) it better|(impressive|excellent|brilliant) (work|analysis|reasoning)'
SYC="$SYC"'|i appreciate (the|your|you) (pushback|feedback|flagging|catching|raising|pointing)'
SYC="$SYC"'|thanks for (catching|flagging|pointing)|good catch on|point taken|i take your point'
SYC="$SYC"'|you raise a (good|valid|fair|important|great) point|that.?s a (valid|fair|reasonable) (concern|point|challenge)'
SYC="$SYC"'|\byou.?re not wrong\b|\bfair enough\b|\bthat.?s fair\b'
SYC="$SYC"'|you (were|are|.?re) right to (push|poke|question|challenge|ask|doubt|flag|call|insist|press)'
SYC="$SYC"'|right to (push back|be sceptical|be skeptical|distrust|not trust)'
SYC="$SYC"'|\b(good|nice|sharp) (call|instinct|catch) (on|there|to)\b|your instinct (was|is) right'
SYC="$SYC"'|^fair (on|point)\b|\bfair (challenge|push)\b|glad you (asked|pushed|caught)'

EFF='(easier|harder|simpler|quicker|cheaper|faster|trickier) than (it looks|expected|you.?d think|i thought)'
EFF="$EFF"'|\b(it.?s|it is|that.?s|that is|this is|which is) (pretty |fairly |quite |very |actually |all )?(easy|simple|trivial|straightforward|quick|cheap|painless|a doddle)\b'
EFF="$EFF"'|\b(easy|trivial|straightforward|quick|cheap|minor|small|simple) (change|fix|job|task|win|work|edit|patch|addition|tweak|refactor|migration|lift)\b'
EFF="$EFF"'|\bhalf a (day|week|hour)\b|\b(hours?|days?|weeks?|minutes?|afternoons?) of work\b'
EFF="$EFF"'|\b(would|will|should|could|might) take (about |roughly |around |~)?(a |an |[0-9]+ ?(ish )?)?(seconds?|minutes?|hours?|days?|weeks?|months?)'
EFF="$EFF"'|\bshould(n.?t)? take (long|much|more than)|\bin (under|less than) (a |an )?(hour|day|minute|week)'
EFF="$EFF"'|\bnot (hard|difficult|much work|a big (deal|change|job))\b|\b(low|high|medium)[- ]effort\b|\bquick win\b'
EFF="$EFF"'|\brough(ly)? estimate\b|\ba (day|week|couple of days|few hours)('"'"'s)? (of )?(work|effort)\b'

PNT='\byour call\b|\bup to you\b|\byou decide\b|(the|that|this) (decision|choice|call) is (yours|for you)|yours to (make|decide|call)'
PNT="$PNT"'|whichever (you|one) (prefer|want|like)|whatever you prefer|either way works|both are (valid|fine|reasonable|good) (options|choices|approaches)'
PNT="$PNT"'|i.?ll leave (it|that|this) (to|with) you|happy to (do|go) either|i can go either way|i (have|hold) no (preference|strong view)|no strong (preference|opinion|view) (here|either way)'
PNT="$PNT"'|((do|would) you want me to|want me to|would you like me to)[^.?!]*\?'
PNT="$PNT"'|which (of (the|these|those) [a-z0-9-]+ )?(do|would) you (want|prefer|like)'
PNT="$PNT"'|say the word|just say|let me know if you( |.?d )(want|like|prefer)|if you want,? i can|i can .{0,30} if you want'
PNT="$PNT"'|if you.?d rather|say (go|if you)|say the word and|and i.?ll (run|build|do|wire|add) it'

HAZ='\b(someone|somebody|a developer|another (dev|developer)|the next (person|dev|developer|agent|maintainer)|a future (dev|developer|maintainer|agent)|anyone|nobody|no.?one) (might|could|would|may|ever|were to|decides? to|forgets? to|accidentally|by accident)'
HAZ="$HAZ"'|\bif (someone|somebody|anyone|a developer) (ever )?(does|did|were|tries|tried|decides|decided|writes|wrote|adds|added|removes|removed)'
HAZ="$HAZ"'|\b(the|a|one) (trap|pitfall|gotcha|footgun) (to avoid|here|is|would be)|\btraps? to avoid\b'
HAZ="$HAZ"'|\bmake sure (not to|you do ?n.?t|nobody|no.?one|it never|that nobody)'
HAZ="$HAZ"'|\bexactly as (it|they) (is|are|was|were)\b|\b(keep|leave) (it|this|that|them) (as (it is|they are|is)|alone|untouched)\b'
HAZ="$HAZ"'|\b(it.?s|that.?s|which is) tempting to\b|\bdo ?n.?t be tempted\b|\blooks natural\b'
HAZ="$HAZ"'|\bin case (someone|somebody|anyone|it ever|that ever)\b|\bso (that )?(nobody|no.?one|someone can.?t)\b'
HAZ="$HAZ"'|\bfuture.?proof'

ALL_BANNED="$CMP|$TIC|$SYC|$EFF|$PNT|$HAZ"

strip_code() { sed '/^[[:space:]]*```/,/^[[:space:]]*```/d' | sed 's/`[^`]*`//g'; }
