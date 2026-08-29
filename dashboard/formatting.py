"""Formatting utilities for the Olist dashboard.

These helpers produce the compact, human‑readable strings that appear in
the dashboard UI.  Nothing here touches the database — all numbers come
from ``queries.py``.

Currency is always R$ (Brazilian Real) unless otherwise noted.
"""

import math


def format_currency(value: float) -> str:
    """Format a numeric value as Brazilian Real.

    - Millions become ``R$16.01M``.
    - Thousands become ``R$99.4K``.
    - Anything smaller is shown as an integer ``R$161``.
    - The value is *always* rounded to the nearest whole unit of the
      chosen suffix before formatting.
    """
    if value is None:
        return "R$ 0"
    abs_val = abs(value)
    if abs_val >= 1_000_000:
        # Millions: one decimal place, e.g. 16.01M
        val = value / 1_000_000
        return f"R$ {val:.2f}M"
    elif abs_val >= 1_000:
        # Thousands: one decimal place, e.g. 99.4K
        val = value / 1_000
        return f"R$ {val:.1f}K"
    else:
        # Integer
        return f"R$ {value:,.0f}"


def format_number(value: int | float) -> str:
    """Format a plain integer with thousands separators."""
    if value is None:
        return "-"
    return f"{value:,}"


def format_percent(value: float) -> str:
    """Format a percentage to one decimal place with a trailing % sign."""
    if value is None:
        return "0.0%"
    return f"{value:.1f}%"


def format_score(score: float) -> str:
    """Format a review score as ``X / 5``."""
    if score is None:
        return "0 / 5"
    return f"{score:.2f} / 5"


def format_count(value: int) -> str:
    """Format a count with thousands separators."""
    if value is None:
        return "-"
    return f"{value:,}"