# Ensemble 152 — Paying the Winners (Settling Game-Over Payouts)

**Date:** 2026-07-24 (the 5pm ensemble — follows the prep record below)
**Repo:** `blackjack-ensemble-blue`, today's `mob next` commits on top of `097684d` (Ensemble 151)
**Participants:** Lada, Daniel, Tom (facilitated by Ted)

---

## What we set out to do

Wire up **settlement**: once a game is over, credit the player's account with their winnings.
Until now the bet was deducted at bet-time (Ensemble 151), but nothing ever paid it back — the
settlement step was just a block of `// TODO` comments in `GameService.execute()`.

## What we actually built

Test-first: we added `whenGameOverPayoutIsAddedToPlayerAccountBalance` to `GameServiceTest`, then
made it green with the minimal wiring in `execute()`:

```java
PlayerResult playerResult = game.playerResults().getFirst();
Optional<PlayerAccount> playerAccount = playerAccountRepository.find(playerResult.playerId());
playerAccount.ifPresent(p -> {
    p.deposit(playerResult.payout());
    playerAccountRepository.save(p);
});
```

Worth noticing: we reached for `deposit(payout)` on the **first** player result — a tracer bullet —
rather than the `win()`/`lose()` loop the prep record predicted. That is the honest tradeoff: it
makes the balance correct for the case we tested, and defers both the win-vs-lose *event*
distinction and the multi-player loop to next time.

Also this session:

- Made `PlayerOutcome.payoff(Bet)` **public** (it was package-private) so the payout calc could be
  reached from the test/application side — flagged as a visibility smell to revisit.
- Threaded the domain `PlayerResult` (playerId + payout) into the service instead of re-deriving
  those values in the application layer.
- Updated the Mission: checked off *"Ensure GameService uses repository for changing PlayerAccount
  state"*; added a new TODO *"Update balance for all players after game is over in GameService."*

## The maths (the interesting part)

Blackjack pays **3:2**. Worked example — start £75, bet £50, get blackjack:

- Place bet → balance `75 − 50 = 25` (stake on the table)
- Blackjack payout `= (int)(2.5 × 50) = 125`
- Final balance `25 + 125 = 150` (net **+£75**)

The test writes the arithmetic out — `75 - 50 + (int)(2.5 * 50)` — instead of a bare `150`, so the
story stays visible in the assertion.

The payoff constants are multipliers on the **total returned** (stake included, because the stake
was already deducted at bet-time): LOSES/BUSTED ×0, PUSH ×1, BEATS/DEALER_BUSTED ×2, BLACKJACK ×2.5.
So `2.5 = 1.0` (stake back) `+ 1.5` (winnings). Equivalently, blackjack **winnings** are 1.5× the bet.

## Where we stopped — the one-to-many step

The wiring only settles `playerResults().getFirst()`. Next move: iterate over the whole
`List<PlayerResult>` so **every** player is paid, not just the first. The way to *drive* that
generalisation with tests is **triangulation** — see below.

---

## Triangulation — how to drive the one-to-many step

**What it is.** Triangulation is a TDD technique (Kent Beck) for forcing a general solution out of
a specific one. You do it by adding a **second example with a different expected value** that the
current, over-specific implementation cannot satisfy. One example can always be passed by faking or
hard-coding; a second, *differing* example gives you two points to "triangulate" from, and the only
honest way to satisfy both is to write the real, general code. Hence the phrase: **this value versus
this other value** — two concrete cases whose answers differ.

**Why we need it here.** Our settlement uses `getFirst()`. With only one player in the test, that's
indistinguishable from a correct loop — a single example can't tell "settle the first player" apart
from "settle every player". To expose the difference we need a second player whose balance change is
**different** from the first's.

**The cycle, concretely.**

**Step 1 — first example (already green).** One player, dealt blackjack, bets 50, starts 75 →
asserts balance `75 - 50 + (int)(2.5 * 50)` = 150. Passes with `getFirst()`.

**Step 2 — a second, differing example (new RED).** Add a *second* player in the same game whose
outcome — and therefore whose expected balance — is **not the same** as the first. For example:
player A gets blackjack (balance ends 150), player B loses/busts (starts 100, bets 50, ends 50).
Assert **both** balances — one value versus the other:

```java
// player A — blackjack:  THIS value
assertThat(accounts.find(playerA)).get().extracting(PlayerAccount::balance)
        .isEqualTo(75 - 50 + (int) (2.5 * 50));   // 150

// player B — loses:      VERSUS this other value
assertThat(accounts.find(playerB)).get().extracting(PlayerAccount::balance)
        .isEqualTo(100 - 50 + 0);                 // 50
```

The `getFirst()` code settles only player A, so player B's assertion fails — **red for the right
reason.** The two different expected values (150 vs 50) are what make the fake impossible.

**Step 3 — generalise (GREEN).** Replace `getFirst()` with a loop over every result:

```java
for (PlayerResult result : game.playerResults()) {
    playerAccountRepository.find(result.playerId()).ifPresent(account -> {
        account.deposit(result.payout());   // or settle(result) — see open questions
        playerAccountRepository.save(account);
    });
}
```

**Step 4 — refactor.** Now that two differing cases pin the behaviour, clean up (e.g. push the
win-vs-lose decision into the domain) with the tests holding you safe.

**The rule of thumb:** the second example must *disagree* with the first. Two players who both win
50 wouldn't triangulate anything — a `getFirst()`-plus-copy could fake it. Choose cases whose
answers differ (win vs lose, blackjack vs push) so the only way to be right about both is the
general solution.

---

## Q&A — deeper dives from the session

**Custom AssertJ assertions (`domain/assertj`).** Project-specific fluent assertions for `Card`,
`Hand`, and `Game`, **generated** by the `assertj-assertions-generator-maven-plugin` (configured in
`pom.xml` for those three classes) and then extended by hand. Standard shape: `Abstract*Assert`
holds the logic, the thin `*Assert` supplies the self-type and a static `assertThat`, and
`BlackjackAssertions extends Assertions` is the single entry point. Regenerate with
`mvn assertj-assertions-generator:generate-assertions`. Hand-written extras: `allCardsFaceUp()`,
`currentPlayerHand()`, and the `firstCard()` / `holeCard()` navigators. Used via a static import so
tests read `assertThat(game).currentPlayerHand().allCardsFaceUp()` with domain-worded failures.

**Asserting on `Optional`.** `assertThat(optional)` returns an `OptionalAssert`: `.isEmpty()` /
`.isPresent()`, `.hasValue(v)` / `.contains(v)`, `.get().extracting(...)` to unwrap and keep
chaining, `.hasValueSatisfying(consumer)`, and `.map(...)`. All null-safe. We already use `.isEmpty()`
and `.get().extracting(PlayerAccount::balance)` in the repo.

**Better `StubDeckBuilder` tests.** The builder earns its keep by hiding the round-robin deal order,
so consuming tests read as intent. Improvements, strongest first: infer the player count and drop
`playerCountOf(n)` (its only job is a self-checksum — removing it deletes the whole "count mismatch"
failure mode and its two guard tests); split `withDealerRanks(...)` from a single `build()` and fix
the inconsistent return type (`buildWithDealerDealtBlackjack` returns `Deck`, its siblings return
`StubDeck`); in the builder's own test, assert on the rank sequence
(`.extracting(Card::rank).containsExactly(...)`) instead of `isEqualTo(new StubDeck(...))` — there's
no `toString`, so equality failures print object references; and optionally add a custom
`StubDeckAssert.hasRanks(...)`. Keep game-scenario helpers in the `*StubDeckFactory` classes, not the
builder.

**The push settlement path.** A push is a tie → `PLAYER_PUSHES_DEALER`, multiplier ×1.0 → payout =
the bet → net zero (stake returned). It works today only because the multiplier folds the
stake-return in; under a winnings-only (×0) model, `deposit(0)` would wrongly **keep** the stake. So
push — together with lose/bust — is exactly the case that pins down which payoff model we commit to,
and it still needs a settlement test.

---

## Lessons learnt

- **Triangulate to drive generalisation.** One example can be faked (`getFirst()`); a second example
  with a *different* expected value forces the real, general code. Make the second case disagree with
  the first (150 vs 50), not merely repeat it.
- **The `2.5` vs `1.5` payoff model isn't cosmetic.** It decides whether settlement must return the
  stake separately; the push and lose paths are where the wrong choice bites. Choose deliberately and
  cover with tests.
- **`deposit(payout)` is a fine tracer bullet but not the end state.** It gets balances right for
  win/push/blackjack, yet it doesn't record the win-vs-lose *event* the prep flagged — that
  distinction lives in `PlayerAccount.win()` / `lose()` and is only visible in the emitted events,
  not the balance.
- **Widening `PlayerOutcome.payoff` to public is a smell.** When you widen visibility just to make a
  caller compile, ask whether the caller belongs there or whether the calc should stay behind the
  domain.
- **Use the object that already carries the data.** Threading `PlayerResult` through the service beat
  re-deriving playerId/payout in the application layer.
- **AssertJ `Optional` + custom assertions keep tests intent-revealing** and give better failure
  messages than raw boolean checks.

## Open questions

- Should the payout calculation stay behind `PlayerOutcome` / `PlayerResult` rather than exposing
  `payoff` publicly?
- Do we want explicit tests for the push and lose settlement paths?
- Commit to `2.5` (total-return) or `1.5` (winnings-only) as the payoff model?
