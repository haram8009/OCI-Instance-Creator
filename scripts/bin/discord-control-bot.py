#!/usr/bin/env python3
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import discord
from discord import app_commands


CONTROL_DIR = Path(os.environ.get("CONTROL_DIR", "/app/control"))
COMMAND_FILE = Path(os.environ.get("CONTROL_COMMAND_FILE", CONTROL_DIR / "command.json"))
STATUS_FILE = Path(os.environ.get("STATUS_FILE", CONTROL_DIR / "status.json"))
BOT_TOKEN = os.environ["DISCORD_BOT_TOKEN"]
GUILD_ID = os.environ.get("DISCORD_GUILD_ID", "").strip()


def parse_ids(value: str) -> set[int]:
  ids: set[int] = set()
  for item in value.split(","):
    item = item.strip()
    if item:
      ids.add(int(item))
  return ids


ALLOWED_USER_IDS = parse_ids(os.environ.get("DISCORD_ALLOWED_USER_IDS", ""))
ALLOWED_ROLE_IDS = parse_ids(os.environ.get("DISCORD_ALLOWED_ROLE_IDS", ""))


def utc_now() -> str:
  return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def write_json_atomic(path: Path, payload: dict) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as tmp:
    json.dump(payload, tmp, ensure_ascii=False)
    tmp.write("\n")
    tmp_path = Path(tmp.name)
  tmp_path.replace(path)


def read_json(path: Path) -> dict:
  if not path.exists():
    return {}
  with path.open() as f:
    return json.load(f)


def is_authorized(interaction: discord.Interaction) -> bool:
  user = interaction.user
  if user.id in ALLOWED_USER_IDS:
    return True

  role_ids = {role.id for role in getattr(user, "roles", [])}
  if ALLOWED_ROLE_IDS and role_ids.intersection(ALLOWED_ROLE_IDS):
    return True

  permissions = getattr(user, "guild_permissions", None)
  return bool(permissions and permissions.administrator)


async def require_authorized(interaction: discord.Interaction) -> bool:
  if is_authorized(interaction):
    return True

  await interaction.response.send_message(
    "You are not allowed to control this retry worker.",
    ephemeral=True,
  )
  return False


class ControlBot(discord.Client):
  def __init__(self) -> None:
    super().__init__(intents=discord.Intents.default())
    self.tree = app_commands.CommandTree(self)

  async def setup_hook(self) -> None:
    if GUILD_ID:
      guild = discord.Object(id=int(GUILD_ID))
      self.tree.copy_global_to(guild=guild)
      synced = await self.tree.sync(guild=guild)
      names = ", ".join(f"/{command.name}" for command in synced)
      print(f"Discord slash commands synced to guild {GUILD_ID}: {names}", flush=True)
      return

    synced = await self.tree.sync()
    names = ", ".join(f"/{command.name}" for command in synced)
    print(f"Discord global slash commands synced: {names}", flush=True)

  async def on_ready(self) -> None:
    print(f"Discord control bot ready as {self.user}", flush=True)


bot = ControlBot()


def command_payload(command: str, interaction: discord.Interaction) -> dict:
  return {
    "command": command,
    "request_id": f"{command}-{int(datetime.now(timezone.utc).timestamp())}-{interaction.user.id}",
    "requested_at": utc_now(),
    "requested_by": {
      "id": str(interaction.user.id),
      "name": str(interaction.user),
    },
    "source": "discord",
  }


@bot.tree.command(name="pause", description="Pause retries after the current OCI attempt finishes.")
async def pause_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  write_json_atomic(COMMAND_FILE, command_payload("pause", interaction))
  await interaction.response.send_message(
    "Pause requested. The current attempt will finish before retries pause.",
    ephemeral=True,
  )


@bot.tree.command(name="resume", description="Resume a paused OCI retry run.")
async def resume_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  write_json_atomic(COMMAND_FILE, command_payload("resume", interaction))
  await interaction.response.send_message("Resume requested.", ephemeral=True)


@bot.tree.command(name="stop", description="Stop the current OCI retry run but keep Discord control online.")
async def stop_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  write_json_atomic(COMMAND_FILE, command_payload("stop", interaction))
  await interaction.response.send_message(
    "Stop requested. Use /restart to start a new run or /shutdown to stop Discord control.",
    ephemeral=True,
  )


@bot.tree.command(name="restart", description="Restart the OCI retry run with a new run id.")
async def restart_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  write_json_atomic(COMMAND_FILE, command_payload("restart", interaction))
  await interaction.response.send_message("Restart requested.", ephemeral=True)


@bot.tree.command(name="shutdown", description="Stop the retry worker and Discord control bot.")
async def shutdown_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  write_json_atomic(COMMAND_FILE, command_payload("shutdown", interaction))
  await interaction.response.send_message(
    "Shutdown requested. Discord control will stop after this command is handled.",
    ephemeral=True,
  )


@bot.tree.command(name="status", description="Show the current OCI retry status.")
async def status_command(interaction: discord.Interaction) -> None:
  if not await require_authorized(interaction):
    return

  status = read_json(STATUS_FILE)
  pending = read_json(COMMAND_FILE)

  if not status:
    await interaction.response.send_message("No retry status has been written yet.", ephemeral=True)
    return

  pending_text = pending.get("command", "none")
  message = (
    f"Run: `{status.get('run_id', 'unknown')}`\n"
    f"Phase: `{status.get('phase', 'unknown')}`\n"
    f"Attempt: `{status.get('attempt', 0)}`\n"
    f"State: `{status.get('state', 'unknown')}`\n"
    f"Job: `{status.get('job_id', 'unknown')}`\n"
    f"Next retry: `{status.get('next_retry', 'unknown')}`\n"
    f"Pending command: `{pending_text}`"
  )
  await interaction.response.send_message(message, ephemeral=True)


bot.run(BOT_TOKEN)
