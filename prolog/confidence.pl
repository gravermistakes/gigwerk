%%%% GigWerk confidence rule, in the language that will actually consume it.
%%%%
%%%% The store exports Prolog facts; this file decides bands over them. Same
%%%% shape as harness_learning.pl consuming outcome_log.pl -- which means the
%%%% booking path and the Aleph path read the same facts through the same door.
%%%%
%%%%   sqlite3 gigwerk.db ".read sql/export_facts.sql" > facts.pl
%%%%   swipl -g run_tests -t halt prolog/confidence.pl
%%%%
%%%% Facts consumed:
%%%%   review(FormSig, PredictionHeld, CriticPassed, JudgeRefuted, At).
%%%%     PredictionHeld :: yes | partial | no
%%%%     CriticPassed   :: 1 | 0
%%%%     JudgeRefuted   :: 1 | 0

:- module(confidence, [band/3, certainty/2, score/2, window_size/1,
                      promotable/2, distinct_forms/2]).
:- use_module(library(lists)).
:- use_module(library(apply)).

:- dynamic user:review/5.   % fact dumps consult into user, so read from there


window_size(15).
threshold(0.80).

%% score(+Review, -Score)
%% matched = prediction held AND critic passed AND judge failed to refute.
%% Any one of the three failing burns a slot -- which is how the adversarial
%% judge spends confidence without spending the human's time.
score(review(_, _, 0, _, _), 0.0) :- !.          % critic failed
score(review(_, _, _, 1, _), 0.0) :- !.          % judge refuted
score(review(_, yes, _, _, _),     1.0) :- !.
score(review(_, partial, _, _, _), 0.5) :- !.
score(review(_, no, _, _, _),      0.0).

%% Most recent first. sort/4 with @>= keys on the timestamp argument and keeps
%% duplicates, which @> would discard.
reviews(Sig, Sorted) :-
    findall(review(Sig,P,C,J,At), user:review(Sig,P,C,J,At), Rs),
    sort(5, @>=, Rs, Sorted).

take(0, _, []) :- !.
take(_, [], []) :- !.
take(N, [H|T], [H|R]) :- N > 0, N1 is N - 1, take(N1, T, R).

window(Sig, Win) :-
    reviews(Sig, Rs), window_size(W), take(W, Rs, Win).

%% Cold start pins the denominator at the window size, so a perfect short
%% record cannot reach threshold. The prior IS the denominator.
lifetime_rate(Sig, Rate) :-
    reviews(Sig, Rs), length(Rs, N), N > 0,
    maplist(score, Rs, Ss), sum_list(Ss, Sum),
    window_size(W),
    ( N < W -> Denom is float(W) ; Denom is float(N) ),
    Rate is Sum / Denom.

window_rate(Sig, Rate) :-
    reviews(Sig, Rs), length(Rs, N), N > 0,
    window_size(W), window(Sig, Win), length(Win, L),
    maplist(score, Win, Ss), sum_list(Ss, Sum),
    ( N < W -> Denom is float(W) ; Denom is float(L) ),
    Rate is Sum / Denom.

%% The conservative rate always wins. A long mediocre record is not laundered
%% by one clean window; a long good record does not survive a broken one.
certainty(Sig, C) :-
    lifetime_rate(Sig, L), window_rate(Sig, Wr),
    C is min(L, Wr).

window_clean(Sig) :-
    window(Sig, Win), Win \== [],
    forall(member(R, Win), score(R, 1.0)).

%% band(+Sig, -Band, -Certainty)
%%   a_autopass     window is CLEAN and certainty >= threshold.
%%                  A is a qualitative claim -- nothing has gone wrong recently
%%                  -- not merely a higher percentage. This closes the 13/15 and
%%                  14/15 gap: a recent failure blocks autopass at any ratio.
%%   b_last_review  at or above threshold but not clean. Probation.
%%   c_needs_review below threshold, or the window has not filled.
band(Sig, Band, C) :-
    reviews(Sig, Rs), length(Rs, N),
    certainty(Sig, C), threshold(T), window_size(W),
    (  N < W                                -> Band = c_needs_review
    ;  window_clean(Sig), C >= T            -> Band = a_autopass
    ;  C >= T                               -> Band = b_last_review
    ;  Band = c_needs_review
    ).

% ==========================================================================
% GENERALIZATION GUARD
%
% Borrowed from continuous-learning-v2's rule that an instinct must appear in
% 2+ projects before global promotion. The point is not the number -- it is
% that a rule which only ever fired in ONE context is indistinguishable from a
% property of that context.
%
% Aleph will happily induce a rule from a single form's history. Promoting it
% to gate logic makes the gate learn that form's accidents. So a candidate rule
% must be supported by evidence from at least MIN_FORMS distinct forms before it
% is even eligible for human review -- and human review still gates it after.
%
% This is the last unguarded edge in the design: everywhere else the loop is
% broken by a human or a deterministic check, but an induced rule reaching the
% gate directly would close it.

min_forms(2).

%% supports(RuleId, FormSig) -- asserted by the learner: this form's history
%% contains an instance the candidate rule covers.
:- dynamic user:supports/2.

distinct_forms(RuleId, N) :-
    findall(F, user:supports(RuleId, F), Fs),
    sort(Fs, Uniq),
    length(Uniq, N).

%% promotable(+RuleId, -Verdict)
%%   eligible_for_review  enough distinct support; a human decides next
%%   too_narrow(N)        supported by N forms, below the floor
promotable(RuleId, Verdict) :-
    distinct_forms(RuleId, N), min_forms(Min),
    (  N >= Min -> Verdict = eligible_for_review
    ;  Verdict = too_narrow(N)
    ).

% ==========================================================================
% tests
% ==========================================================================
:- begin_tests(confidence).

mk(Sig, Good, Bad, BadOld) :-
    retractall(user:review(Sig,_,_,_,_)),
    ( BadOld == old
    -> GoodBase = 1000, BadBase = 0
    ;  GoodBase = 0,    BadBase = 1000 ),
    forall(between(1, Good, I),
           ( At is GoodBase + I, assertz(user:review(Sig, yes, 1, 0, At)) )),
    forall(between(1, Bad, I),
           ( At is BadBase + I,  assertz(user:review(Sig, no, 1, 0, At)) )).

test(clean_full_window_autopasses) :-
    mk(f1, 15, 0, recent), band(f1, B, C),
    assertion(B == a_autopass), assertion(C =:= 1.0).

test(one_recent_failure_blocks_autopass_at_93pct) :-
    mk(f2, 14, 1, recent), band(f2, B, _),
    assertion(B == b_last_review).

test(the_gap_13_of_15) :-
    mk(f3, 13, 2, recent), band(f3, B, _),
    assertion(B == b_last_review).

test(exact_threshold_12_of_15) :-
    mk(f4, 12, 3, recent), band(f4, B, C),
    assertion(B == b_last_review), assertion(abs(C - 0.8) < 0.0001).

test(just_under_11_of_15) :-
    mk(f5, 11, 4, recent), band(f5, B, _),
    assertion(B == c_needs_review).

test(clean_window_does_not_launder_mediocre_lifetime) :-
    mk(f6, 79, 21, old), band(f6, B, C),
    assertion(B == c_needs_review), assertion(C < 0.80).

test(good_lifetime_does_not_survive_broken_window) :-
    mk(f7, 95, 5, recent), band(f7, B, C),
    assertion(B == c_needs_review), assertion(C < 0.70).

test(cold_start_perfect_record_still_low) :-
    mk(f8, 3, 0, recent), band(f8, B, C),
    assertion(B == c_needs_review), assertion(abs(C - 0.2) < 0.0001).

test(judge_refutation_collapses_a_perfect_form) :-
    mk(f9, 15, 0, recent),
    retractall(user:review(f9,_,_,_,_)),
    forall(between(1,15,I), assertz(user:review(f9, yes, 1, 1, I))),
    band(f9, B, C),
    assertion(B == c_needs_review), assertion(C =:= 0.0).

test(rule_from_one_form_is_too_narrow) :-
    retractall(user:supports(r1, _)),
    assertz(user:supports(r1, form_a)),
    assertz(user:supports(r1, form_a)),   % same form twice is still one form
    promotable(r1, V),
    assertion(V == too_narrow(1)).

test(rule_seen_in_two_forms_is_eligible) :-
    retractall(user:supports(r2, _)),
    assertz(user:supports(r2, form_a)),
    assertz(user:supports(r2, form_b)),
    promotable(r2, V),
    assertion(V == eligible_for_review).

test(eligible_is_not_the_same_as_promoted) :-
    % There is deliberately no predicate that promotes. Eligibility is the
    % most this file will ever say; the human is the only path to gate logic.
    assertion(\+ current_predicate(confidence:promote/1)).

test(partials_score_half) :-
    retractall(user:review(f10,_,_,_,_)),
    forall(between(1,15,I), assertz(user:review(f10, partial, 1, 0, I))),
    band(f10, B, C),
    assertion(B == c_needs_review), assertion(abs(C - 0.5) < 0.0001).

:- end_tests(confidence).
