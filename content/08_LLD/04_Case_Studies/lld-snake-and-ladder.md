---
title: 04 - LLD Snake and Ladder Game
description: A low-level design case study for a Snake and Ladder board game, modeling the board, players, dice, snakes, ladders, and game flow using the Strategy pattern and clean class design.
tags: [lld, case-study, snake-ladder, game, strategy, layer-7]
status: draft
difficulty: intermediate
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Snake and Ladder Game

> Design a Snake and Ladder board game supporting multiple players, configurable board sizes, different dice strategies, and clean game state management.

---

## Quick Reference

**Requirements:**
- Configurable board with N cells, multiple snakes and ladders
- 2-4 players taking turns rolling dice
- Snakes move players down, ladders move players up
- First player to reach or exceed the final cell wins
- Optional rule: exact landing on final cell required (configurable)

**Key patterns used:**
- **Strategy** for dice rolling (single die, double dice, loaded dice for testing)
- **Factory** for board creation with different configurations
- **Observer** for game event notifications (move, snake bite, ladder climb, win)

---

## Class Design

```python
from dataclasses import dataclass, field
from typing import Protocol, Callable
from enum import Enum
import random


# --- Dice Strategy ---
class DiceStrategy(Protocol):
    def roll(self) -> int: ...

class SingleDice:
    def roll(self) -> int:
        return random.randint(1, 6)

class DoubleDice:
    def roll(self) -> int:
        return random.randint(1, 6) + random.randint(1, 6)

class FixedDice:
    """For testing - returns predetermined values."""
    def __init__(self, values: list[int]):
        self._values = iter(values)

    def roll(self) -> int:
        return next(self._values)


# --- Board Elements ---
@dataclass(frozen=True)
class Snake:
    head: int    # start position (higher)
    tail: int    # end position (lower)

    def __post_init__(self):
        if self.head <= self.tail:
            raise ValueError(f"Snake head ({self.head}) must be above tail ({self.tail})")


@dataclass(frozen=True)
class Ladder:
    bottom: int  # start position (lower)
    top: int     # end position (higher)

    def __post_init__(self):
        if self.bottom >= self.top:
            raise ValueError(f"Ladder bottom ({self.bottom}) must be below top ({self.top})")


@dataclass
class Player:
    name: str
    position: int = 0
    has_won: bool = False


# --- Game Events ---
class GameEvent(Enum):
    MOVE = "move"
    SNAKE = "snake"
    LADDER = "ladder"
    WIN = "win"
    BOUNCE = "bounce"  # exceeded board size, bounced back


@dataclass
class GameEventData:
    event: GameEvent
    player: Player
    details: dict


# --- Board ---
class Board:
    def __init__(self, size: int, snakes: list[Snake], ladders: list[Ladder]):
        self.size = size
        self._snakes = {s.head: s.tail for s in snakes}
        self._ladders = {l.bottom: l.top for l in ladders}

        # Validate: no overlap between snake heads and ladder bottoms
        overlap = set(self._snakes.keys()) & set(self._ladders.keys())
        if overlap:
            raise ValueError(f"Overlap at positions: {overlap}")

    def resolve_position(self, position: int) -> tuple[int, GameEvent | None]:
        """Apply snake/ladder at the given position."""
        if position in self._snakes:
            return self._snakes[position], GameEvent.SNAKE
        if position in self._ladders:
            return self._ladders[position], GameEvent.LADDER
        return position, None

    @classmethod
    def standard_10x10(cls) -> "Board":
        """Standard 100-cell board with preset snakes and ladders."""
        return cls(
            size=100,
            snakes=[
                Snake(16, 6), Snake(47, 26), Snake(49, 11),
                Snake(56, 53), Snake(62, 19), Snake(64, 60),
                Snake(87, 24), Snake(93, 73), Snake(95, 75), Snake(98, 78),
            ],
            ladders=[
                Ladder(1, 38), Ladder(4, 14), Ladder(9, 31),
                Ladder(21, 42), Ladder(28, 84), Ladder(36, 44),
                Ladder(51, 67), Ladder(71, 91), Ladder(80, 100),
            ],
        )


# --- Game Engine ---
class SnakeAndLadderGame:
    def __init__(self, board: Board, players: list[Player],
                 dice: DiceStrategy, require_exact_finish: bool = False):
        self._board = board
        self._players = players
        self._dice = dice
        self._require_exact = require_exact_finish
        self._current_player_idx = 0
        self._listeners: list[Callable[[GameEventData], None]] = []
        self._game_over = False

    def on_event(self, callback: Callable[[GameEventData], None]) -> None:
        self._listeners.append(callback)

    def _emit(self, event: GameEvent, player: Player, **details) -> None:
        data = GameEventData(event=event, player=player, details=details)
        for listener in self._listeners:
            listener(data)

    @property
    def current_player(self) -> Player:
        return self._players[self._current_player_idx]

    def play_turn(self) -> Player | None:
        """Play one turn. Returns the winner if the game is over."""
        if self._game_over:
            raise ValueError("Game is already over")

        player = self.current_player
        roll = self._dice.roll()
        new_position = player.position + roll

        # Check board boundary
        if new_position > self._board.size:
            if self._require_exact:
                # Bounce back
                overshoot = new_position - self._board.size
                new_position = self._board.size - overshoot
                self._emit(GameEvent.BOUNCE, player,
                           roll=roll, bounced_to=new_position)
            else:
                new_position = self._board.size

        # Apply snakes/ladders
        old_pos = player.position
        resolved, event = self._board.resolve_position(new_position)

        if event == GameEvent.SNAKE:
            self._emit(GameEvent.SNAKE, player,
                       roll=roll, from_pos=new_position, to_pos=resolved)
        elif event == GameEvent.LADDER:
            self._emit(GameEvent.LADDER, player,
                       roll=roll, from_pos=new_position, to_pos=resolved)

        player.position = resolved
        self._emit(GameEvent.MOVE, player,
                   roll=roll, from_pos=old_pos, to_pos=player.position)

        # Check win
        if player.position >= self._board.size:
            player.has_won = True
            self._game_over = True
            self._emit(GameEvent.WIN, player, final_position=player.position)
            return player

        # Next player
        self._current_player_idx = (self._current_player_idx + 1) % len(self._players)
        return None

    def play_full_game(self, max_turns: int = 1000) -> Player:
        """Play until someone wins."""
        for _ in range(max_turns):
            winner = self.play_turn()
            if winner:
                return winner
        raise RuntimeError(f"No winner after {max_turns} turns")


# --- Usage ---
def event_logger(event: GameEventData) -> None:
    p = event.player
    d = event.details
    if event.event == GameEvent.SNAKE:
        print(f"  {p.name} hit a SNAKE at {d['from_pos']} -> {d['to_pos']}")
    elif event.event == GameEvent.LADDER:
        print(f"  {p.name} climbed a LADDER at {d['from_pos']} -> {d['to_pos']}")
    elif event.event == GameEvent.WIN:
        print(f"  {p.name} WINS at position {d['final_position']}!")
    elif event.event == GameEvent.MOVE:
        print(f"  {p.name} rolled {d['roll']}: {d['from_pos']} -> {d['to_pos']}")


board = Board.standard_10x10()
players = [Player("Alice"), Player("Bob"), Player("Charlie")]
game = SnakeAndLadderGame(board, players, SingleDice())
game.on_event(event_logger)

winner = game.play_full_game()
print(f"\nWinner: {winner.name}")
```

---

## SOLID Analysis

- **SRP**: `Board` manages cell resolution. `SnakeAndLadderGame` manages turn flow. `DiceStrategy` handles randomness.
- **OCP**: New dice types and board configurations are added without modifying the game engine.
- **Strategy**: Dice rolling is pluggable - use `FixedDice` for deterministic testing.
- **Observer**: Event listeners decouple display/logging from game logic.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[strategy-pattern|Strategy Pattern]]
- [[observer-pattern|Observer Pattern]]
- [[factory-method|Factory Method Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
