from __future__ import annotations

import asyncio
import io
import discord
from discord.ext import commands

from config import MANUAL_DEOBF_CHANNEL_ID
from deobfuscators.io_resolver import resolve_input
from deobfuscators.router import deobfuscate_script


ACCENT = discord.Color.from_rgb(90, 120, 255)


def panel_embed(
    title: str,
    description: str | None = None,
    *,
    color: discord.Color = ACCENT,
) -> discord.Embed:
    embed = discord.Embed(
        title=title,
        description=description,
        color=color,
    )
    embed.set_footer(text="Radium Deobfuscator • automatic + manual fallback")
    return embed


class BackendSelect(discord.ui.Select):
    def __init__(self):
        options = [
            discord.SelectOption(
                label="Auto-Detect",
                value="auto",
                description="Detect the obfuscator using structural fingerprints",
                emoji="🔎",
                default=True,
            ),
            discord.SelectOption(
                label="IronBrew 1",
                value="ib1",
                description="Installed ib1 CLI",
                emoji="1️⃣",
            ),
            discord.SelectOption(
                label="IronBrew 2 / AztupBrew",
                value="ib2",
                description="IronBrew 2 and AztupBrew backend",
                emoji="2️⃣",
            ),
            discord.SelectOption(
                label="IronBrew 3",
                value="ib3",
                description="IronBrew 3 backend",
                emoji="3️⃣",
            ),
            discord.SelectOption(
                label="LuaObfuscator",
                value="luaobfuscator",
                description="LuaObfuscator / IB2-family backend",
                emoji="🧪",
            ),
        ]

        super().__init__(
            placeholder="Auto-Detect",
            min_values=1,
            max_values=1,
            options=options,
            row=0,
        )

    async def callback(self, interaction: discord.Interaction):
        self.view.selected = self.values[0]

        for option in self.options:
            option.default = option.value == self.view.selected

        await interaction.response.edit_message(
            embed=self.view.make_embed(),
            view=self.view,
        )


class RunButton(discord.ui.Button):
    def __init__(self):
        super().__init__(
            label="Deobfuscate",
            style=discord.ButtonStyle.primary,
            emoji="▶️",
            row=1,
        )

    async def callback(self, interaction: discord.Interaction):
        if interaction.user.id != self.view.owner_id:
            await interaction.response.send_message(
                "This menu belongs to someone else.",
                ephemeral=True,
            )
            return

        await interaction.response.defer()

        if not self.view.future.done():
            self.view.future.set_result(self.view.selected)


class CancelButton(discord.ui.Button):
    def __init__(self):
        super().__init__(
            label="Cancel",
            style=discord.ButtonStyle.secondary,
            emoji="✖️",
            row=1,
        )

    async def callback(self, interaction: discord.Interaction):
        if interaction.user.id != self.view.owner_id:
            await interaction.response.send_message(
                "This menu belongs to someone else.",
                ephemeral=True,
            )
            return

        await interaction.response.edit_message(
            embed=panel_embed(
                "Deobfuscator",
                "Cancelled.",
                color=discord.Color.dark_grey(),
            ),
            view=None,
        )

        if not self.view.future.done():
            self.view.future.set_result(None)

        self.view.stop()


class DeobfuscatorView(discord.ui.View):
    def __init__(self, owner_id: int):
        super().__init__(timeout=120)

        self.owner_id = owner_id
        self.selected = "auto"

        loop = asyncio.get_running_loop()
        self.future = loop.create_future()

        self.add_item(BackendSelect())
        self.add_item(RunButton())
        self.add_item(CancelButton())

    def make_embed(self) -> discord.Embed:
        display = {
            "auto": "Auto-Detect",
            "ib1": "IronBrew 1",
            "ib2": "IronBrew 2 / AztupBrew",
            "ib3": "IronBrew 3",
            "luaobfuscator": "LuaObfuscator",
        }.get(self.selected, self.selected)

        embed = panel_embed(
            "Deobfuscator",
            (
                "Select the obfuscator below, then press **Deobfuscate**.\n\n"
                f"**Selected:** `{display}`"
            ),
        )

        embed.add_field(
            name="Input",
            value=(
                "URL • attachment • reply • Lua codeblock • raw Lua"
            ),
            inline=False,
        )

        return embed

    async def on_timeout(self):
        if not self.future.done():
            self.future.set_result(None)


def failure_embed(kind: str, error: Exception | str) -> discord.Embed:
    embed = panel_embed(
        "Automatic Deobfuscation Failed",
        (
            f"I couldn't automatically deobfuscate this **{kind}** script.\n\n"
            f"Upload the **original obfuscated file** in "
            f"<#{MANUAL_DEOBF_CHANNEL_ID}> and it can be handled manually."
        ),
        color=discord.Color.red(),
    )

    error = str(error).strip()

    if error:
        embed.add_field(
            name="Error",
            value=f"```text\n{error[:900]}\n```",
            inline=False,
        )

    return embed


def setup_deobf_commands(bot: commands.Bot):
    @bot.hybrid_command(
        name="supported",
        description="Show supported and detectable obfuscators.",
    )
    async def supported(ctx: commands.Context):
        embed = panel_embed(
            "Supported Obfuscators",
            "Automatic deobfuscators and detector coverage.",
        )

        embed.add_field(
            name="Automatic",
            value=(
                "• **IronBrew 1**\n"
                "• **IronBrew 2 / AztupBrew**\n"
                "• **IronBrew 3**\n"
                "• **LuaObfuscator**"
            ),
            inline=False,
        )

        embed.add_field(
            name="Detection / Manual Fallback",
            value=(
                "The sample-based detector can also identify other known "
                "families such as **Luraph**, **MoonSec**, **MoonVeil**, and "
                "**Prometheus**. Unsupported detections are sent to the "
                f"manual channel: <#{MANUAL_DEOBF_CHANNEL_ID}>."
            ),
            inline=False,
        )

        await ctx.send(
            embed=embed,
            ephemeral=bool(ctx.interaction),
        )

    @bot.hybrid_command(
        name="deobfuscate",
        aliases=["deobf"],
        description="Deobfuscate a Lua script with an interactive backend selector.",
    )
    async def deobfuscate_command(
        ctx: commands.Context,
        *,
        source: str | None = None,
    ):
        # Resolve first so the menu only appears for valid input.
        try:
            code = await resolve_input(ctx, source)
        except Exception as exc:
            await ctx.send(
                embed=failure_embed("input", exc),
                ephemeral=bool(ctx.interaction),
            )
            return

        if not code.strip():
            await ctx.send(
                embed=failure_embed("input", "Input script is empty."),
                ephemeral=bool(ctx.interaction),
            )
            return

        view = DeobfuscatorView(ctx.author.id)

        message = await ctx.send(
            embed=view.make_embed(),
            view=view,
        )

        selected = await view.future

        if selected is None:
            try:
                await message.edit(
                    embed=panel_embed(
                        "Deobfuscator",
                        "Selection expired or was cancelled.",
                        color=discord.Color.dark_grey(),
                    ),
                    view=None,
                )
            except discord.HTTPException:
                pass
            return

        display = {
            "auto": "Auto-Detect",
            "ib1": "IronBrew 1",
            "ib2": "IronBrew 2 / AztupBrew",
            "ib3": "IronBrew 3",
            "luaobfuscator": "LuaObfuscator",
        }.get(selected, selected)

        processing = panel_embed(
            "Deobfuscating",
            f"Running **{display}**...",
            color=discord.Color.orange(),
        )

        await message.edit(
            embed=processing,
            view=None,
        )

        try:
            result, detected = await deobfuscate_script(
                selected,
                code,
            )

            done = panel_embed(
                "Deobfuscation Complete",
                "The deobfuscated output is attached below.",
                color=discord.Color.green(),
            )

            done.add_field(
                name="Detected",
                value=f"`{detected.name}`",
                inline=True,
            )

            done.add_field(
                name="Backend",
                value=f"`{detected.kind}`",
                inline=True,
            )

            done.add_field(
                name="Confidence",
                value=f"`{detected.confidence:.0%}`",
                inline=True,
            )

            await message.edit(embed=done)

            await ctx.reply(
                file=discord.File(
                    io.BytesIO(
                        result.encode(
                            "utf-8",
                            errors="replace",
                        )
                    ),
                    filename="deobfuscated.lua",
                ),
                mention_author=False,
            )

        except Exception as exc:
            await message.edit(
                embed=failure_embed(display, exc),
                view=None,
            )
