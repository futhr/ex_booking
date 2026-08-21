# Agent Instructions

Read and follow `CLAUDE.md` first. It is the canonical repo contract for
architecture, hard rules, the documentation system, quality gates, and the
referenced `.claude/` standards and skills.

Do not duplicate or reinterpret those rules here. This file exists so agents
outside Claude Code can discover the same project instructions quickly.

Canonical skills live only under `.claude/skills/` and are selected automatically
from their descriptions. Clients without native skill discovery should read the
matching `SKILL.md` there and run `mix check` before handing off.
