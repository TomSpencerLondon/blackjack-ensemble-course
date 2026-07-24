# Prep Session — Wiring Game-Over Payouts (before Ensemble 152)

**Date:** 2026-07-24 (prep for the 5pm ensemble, "Ensemble 152")
**Repo:** `blackjack-ensemble-blue` @ `097684d` (Ensemble 151)
**Workspace lesson produced:** `lessons/0004-paying-the-winners.html`

---

## What triggered this record

Lesson 0002's hands-on task (add a two-ace test) went **green on arrival** — it exercised
existing `Hand.value()` behaviour rather than driving new code. Tom's feedback: *"it was helpful
to run the test, but it didn't lead to me adding new functionality."* Correct critique — that task
taught **reading**, not TDD. The fix: make the next lesson a genuine **RED-first** cycle tied to the
work he'll actually do next session.

## The trajectory we found (so lessons aim where the work is)

Reading the repo — not guessing — the next feature is spelled out **as pseudocode** in
`GameService.execute()` (lines ~93–98):

```java
if (game.isGameOver()) {
    gameMonitor.gameCompleted(game);
    gameRepository.saveOutcome(game);
    // loop through all playerIds in the Game:
        // retrieved PlayerAccount from Repository
        // playerAccount.win(payout, playerOutcome)
        // repository.save(playerAccount)
}
```

- Last session (151) did **money OUT**: `placePlayerBets` → `account.bet(amount)` → balance − bet.
- Next is the mirror: **money IN** at game-over → `account.win(payout, outcome)` → balance + payout.
- The domain is **already finished**: `Game.playerResults()` → `PlayerResult{ playerId(), outcome(),
  payout() }`, and `PlayerAccount.win(payout, outcome)` / `lose(outcome)` already exist. The gap is
  purely **application-layer wiring**.

## The RED→GREEN cycle — verified empirically (in a throwaway git worktree, then reverted)

Rather than reason about correctness (the mistake that made 0002 feel weak), the whole cycle was
**run** against a scratch `git worktree` off `HEAD`, then torn down so the real repo stayed pristine
for the ensemble.

**RED test** added to `GameServiceTest` (player beats dealer, 2× payoff):
```java
PlayerAccountRepository accounts = PlayerAccountRepository.withNextId(9);
PlayerAccount account = PlayerAccount.register("winner");
account.deposit(50); accounts.save(account);
GameService gameService = GameService.createForTest(new StubShuffler(), accounts);
Deck deck = new StubDeck(Rank.QUEEN, Rank.EIGHT, Rank.TEN, Rank.JACK); // player 20 vs dealer 18
gameService.createGame(List.of(PlayerId.of(9)), new Shoe(List.of(deck)));
gameService.placePlayerBets(List.of(new PlayerBet(PlayerId.of(9), Bet.of(11))));
gameService.initialDeal();
gameService.playerStands();
assertThat(accounts.find(PlayerId.of(9))).get().extracting(PlayerAccount::balance)
        .isEqualTo(50 - 11 + 22); // 61
```
→ **Failed for the right reason:** `expected: 61 but was: 39` (bet deducted, payout never added).

**GREEN** (minimal wiring in `execute()`):
```java
for (PlayerResult result : game.playerResults()) {
    playerAccountRepository.find(result.playerId()).ifPresent(account -> {
        account.win(result.payout(), result.outcome());
        playerAccountRepository.save(account);
    });
}
```
→ GameServiceTest 8/8 green; **full suite 245/245 green**. (Full version with a
`payout() > 0 ? win : lose` branch also verified 245 green.)

## Facts pinned down (authoritative, from the code)

- **Deal order is alternating**: card1→player, card2→dealer, card3→player, card4→dealer. Proven by
  `SinglePlayerOutcomeTest.playerBeatsDealer` using `StubDeck(QUEEN, EIGHT, TEN, JACK)` → player
  QUEEN+TEN=20, dealer EIGHT+JACK=18. (The two-per-line layout in the stub factories is misleading —
  read it column-wise.)
- **`PlayerOutcome` payoff is a multiplier on the *total returned*, not profit**, and the bet is
  already deducted at bet-time: BEATS/DEALER_BUSTED ×2, BLACKJACK ×2.5, PUSH ×1, BUSTED/LOSES ×0.
- **`win()` vs `lose()`**: `win(payout, outcome)` enqueues `PlayerWonGame` (balance += payout);
  `lose(outcome)` enqueues `PlayerLostGame` (balance unchanged — money already gone).

## The likely arc tonight (interleaved reds)

1. **win path** — done in the lesson (tracer bullet).
2. **lose/push branch** — a "player busts, balance unchanged, `PlayerLostGame` recorded" test forces
   `if (result.payout() > 0) win else lose`. (Win-only code records the *wrong event* for a bust.)
3. **multi-player** — two accounts/two outcomes forces `placePlayerBets` to stop faking with
   `getFirst()` and loop all bets; then delete the commented-out `// if (playerAccountRepository
   != null)` scaffold (the **contract** step).

## Teaching lessons captured

- **A test that's green on arrival teaches reading, not TDD.** Skill-building tasks must start RED
  and drive code that doesn't exist yet.
- **Aim lessons where the *next* work is**, discovered by reading the repo (here: the pseudocode in
  `execute()`), not by inventing plausible exercises.
- **Verify the cycle empirically before shipping a lesson** — run RED→GREEN in an isolated worktree
  and revert — so the numbers in the lesson (39 → 61) are real, not asserted.
