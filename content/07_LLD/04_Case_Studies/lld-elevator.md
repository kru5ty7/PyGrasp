---
title: 03 - LLD Elevator System
description: A low-level design case study for an elevator system, modeling elevator scheduling, floor requests, direction management, and state machines using the Observer and Strategy patterns.
tags: [lld, case-study, elevator, state-machine, observer, layer-7]
status: draft
difficulty: advanced
layer: 7
domain: lld
created: 2026-05-18
---

# LLD: Elevator System

> Design an elevator control system that manages multiple elevators, handles floor requests from halls and cabins, and optimizes scheduling to minimize wait time.

---

## Quick Reference

**Requirements:**
- Multiple elevators serving N floors
- Hall call buttons (up/down per floor) and cabin buttons (destination floor)
- Elevator scheduling: assign the best elevator to a hall request
- Direction management: continue in current direction, picking up compatible requests
- State machine: idle, moving up, moving down, door open

**Key patterns used:**
- **State** pattern for elevator states (idle, moving, door-open)
- **Strategy** for elevator scheduling algorithms (nearest, LOOK, SCAN)
- **Observer** for display updates when elevator state changes
- **Command** for encapsulating floor requests

---

## Class Design

```python
from dataclasses import dataclass, field
from enum import Enum
from typing import Protocol, Callable
from collections import deque


class Direction(Enum):
    UP = "up"
    DOWN = "down"
    IDLE = "idle"


class DoorState(Enum):
    OPEN = "open"
    CLOSED = "closed"


@dataclass
class FloorRequest:
    floor: int
    direction: Direction | None = None  # None for cabin requests
    source: str = "cabin"  # "cabin" or "hall"


class ElevatorObserver(Protocol):
    def on_floor_reached(self, elevator_id: str, floor: int) -> None: ...
    def on_direction_changed(self, elevator_id: str, direction: Direction) -> None: ...


class Elevator:
    """Single elevator with LOOK algorithm scheduling."""

    def __init__(self, elevator_id: str, min_floor: int, max_floor: int):
        self.id = elevator_id
        self.min_floor = min_floor
        self.max_floor = max_floor
        self.current_floor = 1
        self.direction = Direction.IDLE
        self.door = DoorState.CLOSED
        self._up_stops: set[int] = set()
        self._down_stops: set[int] = set()
        self._observers: list[ElevatorObserver] = []

    def add_observer(self, observer: ElevatorObserver) -> None:
        self._observers.append(observer)

    def request_floor(self, floor: int) -> None:
        """Cabin button pressed - add destination."""
        if floor > self.current_floor:
            self._up_stops.add(floor)
        elif floor < self.current_floor:
            self._down_stops.add(floor)
        # If idle, start moving toward the request
        if self.direction == Direction.IDLE:
            self.direction = Direction.UP if floor > self.current_floor else Direction.DOWN

    def add_hall_request(self, floor: int, direction: Direction) -> None:
        """Dispatch assigns a hall request to this elevator."""
        if direction == Direction.UP:
            self._up_stops.add(floor)
        else:
            self._down_stops.add(floor)
        if self.direction == Direction.IDLE:
            self.direction = Direction.UP if floor > self.current_floor else Direction.DOWN

    def step(self) -> str:
        """Simulate one time step. Returns description of action."""
        if self.direction == Direction.IDLE:
            return f"Elevator {self.id}: idle at floor {self.current_floor}"

        if self.direction == Direction.UP:
            return self._step_up()
        else:
            return self._step_down()

    def _step_up(self) -> str:
        self.current_floor += 1
        self._notify_floor_reached()

        if self.current_floor in self._up_stops:
            self._up_stops.discard(self.current_floor)
            self.door = DoorState.OPEN
            action = f"Elevator {self.id}: stopped at floor {self.current_floor} (UP)"
            self.door = DoorState.CLOSED
        else:
            action = f"Elevator {self.id}: passing floor {self.current_floor} (UP)"

        # Check if we should continue up or reverse
        if not self._up_stops or all(f <= self.current_floor for f in self._up_stops):
            if self._down_stops:
                self.direction = Direction.DOWN
                self._notify_direction_changed()
            else:
                self.direction = Direction.IDLE
                self._notify_direction_changed()

        return action

    def _step_down(self) -> str:
        self.current_floor -= 1
        self._notify_floor_reached()

        if self.current_floor in self._down_stops:
            self._down_stops.discard(self.current_floor)
            self.door = DoorState.OPEN
            action = f"Elevator {self.id}: stopped at floor {self.current_floor} (DOWN)"
            self.door = DoorState.CLOSED
        else:
            action = f"Elevator {self.id}: passing floor {self.current_floor} (DOWN)"

        if not self._down_stops or all(f >= self.current_floor for f in self._down_stops):
            if self._up_stops:
                self.direction = Direction.UP
                self._notify_direction_changed()
            else:
                self.direction = Direction.IDLE
                self._notify_direction_changed()

        return action

    @property
    def pending_stops(self) -> int:
        return len(self._up_stops) + len(self._down_stops)

    def _notify_floor_reached(self) -> None:
        for obs in self._observers:
            obs.on_floor_reached(self.id, self.current_floor)

    def _notify_direction_changed(self) -> None:
        for obs in self._observers:
            obs.on_direction_changed(self.id, self.direction)


# --- Scheduling Strategy ---
class SchedulingStrategy(Protocol):
    def select_elevator(self, elevators: list[Elevator],
                        floor: int, direction: Direction) -> Elevator: ...


class NearestElevatorStrategy:
    """Assign to the nearest elevator going in the same direction, or nearest idle."""
    def select_elevator(self, elevators: list[Elevator],
                        floor: int, direction: Direction) -> Elevator:
        # Prefer elevators going in the right direction
        compatible = [
            e for e in elevators
            if e.direction == direction and (
                (direction == Direction.UP and e.current_floor <= floor) or
                (direction == Direction.DOWN and e.current_floor >= floor)
            )
        ]
        if compatible:
            return min(compatible, key=lambda e: abs(e.current_floor - floor))

        # Fall back to idle elevators
        idle = [e for e in elevators if e.direction == Direction.IDLE]
        if idle:
            return min(idle, key=lambda e: abs(e.current_floor - floor))

        # Last resort: least loaded elevator
        return min(elevators, key=lambda e: e.pending_stops)


# --- Elevator Controller ---
class ElevatorController:
    def __init__(self, num_elevators: int, num_floors: int,
                 strategy: SchedulingStrategy):
        self.elevators = [
            Elevator(f"E{i}", 1, num_floors)
            for i in range(num_elevators)
        ]
        self._strategy = strategy

    def hall_request(self, floor: int, direction: Direction) -> str:
        """Someone pressed a hall button."""
        elevator = self._strategy.select_elevator(
            self.elevators, floor, direction
        )
        elevator.add_hall_request(floor, direction)
        return f"Assigned {elevator.id} to floor {floor} ({direction.value})"

    def cabin_request(self, elevator_id: str, floor: int) -> None:
        """Someone pressed a floor button inside the cabin."""
        elevator = next(e for e in self.elevators if e.id == elevator_id)
        elevator.request_floor(floor)

    def simulate_step(self) -> list[str]:
        """Advance all elevators by one step."""
        return [e.step() for e in self.elevators]

    def status(self) -> list[dict]:
        return [
            {"id": e.id, "floor": e.current_floor,
             "direction": e.direction.value, "stops": e.pending_stops}
            for e in self.elevators
        ]


# --- Usage ---
controller = ElevatorController(3, 10, NearestElevatorStrategy())

# Hall requests
print(controller.hall_request(5, Direction.UP))
print(controller.hall_request(8, Direction.DOWN))
print(controller.hall_request(3, Direction.UP))

# Cabin request
controller.cabin_request("E0", 7)

# Simulate
for step in range(8):
    actions = controller.simulate_step()
    for a in actions:
        if "idle" not in a:
            print(f"  Step {step}: {a}")

print("\nFinal status:")
for s in controller.status():
    print(f"  {s}")
```

---

## SOLID Analysis

- **SRP**: `Elevator` manages its own movement. `SchedulingStrategy` handles elevator selection. `ElevatorController` coordinates.
- **OCP**: New scheduling algorithms (LOOK, SCAN, destination dispatch) are added as new strategy classes.
- **Observer**: Display boards can observe elevator state changes without coupling to the elevator logic.
- **State**: The elevator's behavior depends on its direction (UP, DOWN, IDLE), which acts as an implicit state machine.

---

## Related Notes

- [[solid-principles|SOLID Principles]]
- [[observer-pattern|Observer Pattern]]
- [[strategy-pattern|Strategy Pattern]]
- [[design-patterns-overview|Design Patterns Overview]]
