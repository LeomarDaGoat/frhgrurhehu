import os
import re
import io
import json
import uuid
import asyncio
import tempfile
import sys
from pathlib import Path
from typing import Optional

import aiohttp
import discord
from discord.ext import commands
from discord.ext import tasks as discord_tasks

import config

try:
    import shit
except ImportError:
    shit = None


# ============================================================
# PATHS / CONFIG
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

COMMAND_PREFIX = "."

FREE_GUILD_ID = 1550879653487575162
FREE_GUILD_ID2 = 1551983418659835904

PAID_GUILD_ID = 1551579495557898343
PAID_CATEGORY_ID = 1551861546135593041
DEOBF_CHANNEL_ID = 1551935333032271882

PAID_USERS_FILE = BASE_DIR / "paid_users.json"

MANUAL_DEOBF_CHANNEL_ID = getattr(
    config,
    "MANUAL_DEOBF_CHANNEL_ID",
    1550879929019662406,
)

DEOBF_TIMEOUT = getattr(
    config,
    "DEOBF_TIMEOUT",
    180,
)

# Sources related to these markers are intentionally excluded from
# deobfuscation. Matching is case-insensitive and applies to URLs,
# filenames, raw Lua, replies, attachments after download, and nested
# loader/source references inside the submitted code.
DEOBFUSCATION_BLACKLIST = (
    "beanzz.wtf",
    "orionmain.lua",
)


def is_deobfuscation_blacklisted(*values):
    for value in values:
        if value is None:
            continue

        normalized = str(value).lower()
        normalized = normalized.replace("\\/", "/")
        normalized = normalized.replace("\\x2f", "/")
        normalized = normalized.replace("\\x2e", ".")
        normalized = normalized.replace("\\046", ".")
        normalized = normalized.replace("\\057", "/")
        normalized = re.sub(r"[\u200b\u200c\u200d\ufeff]", "", normalized)

        if any(marker in normalized for marker in DEOBFUSCATION_BLACKLIST):
            return True

    return False

IB1_ROOT = Path(
    getattr(
        config,
        "IB1_ROOT",
        BASE_DIR / "funnyib1",
    )
)

IB1_CLI_PATH = Path(
    getattr(
        config,
        "IB1_CLI_PATH",
        IB1_ROOT / "cli.py",
    )
)

IB1_LUAU_PATH = Path(
    getattr(
        config,
        "IB1_LUAU_PATH",
        IB1_ROOT / "luau.exe",
    )
)

IB2_CLI_PATH = Path(
    getattr(
        config,
        "IB2_CLI_PATH",
        BASE_DIR / "smth" / "CLI.exe",
    )
)

IB2_ROOT = Path(
    getattr(
        config,
        "IB2_ROOT",
        IB2_CLI_PATH.parent,
    )
)

LUAOBF_DIRECTORY = Path(
    getattr(
        config,
        "LUAOBF_DIRECTORY",
        BASE_DIR / "LuaObfuscator-Deobfuscator",
    )
)

LUAOBF_MAIN = getattr(
    config,
    "LUAOBF_MAIN",
    "index.js",
)

PROMETHEUS_DIRECTORY = Path(
    getattr(
        config,
        "PROMETHEUS_DIRECTORY",
        r"C:\Users\Bitra\Downloads\deobf-bot-updated\deobf-bot-updated\son",
    )
)

PROMETHEUS_MAIN = getattr(
    config,
    "PROMETHEUS_MAIN",
    "bin/pdeobf.js",
)

CLYDE_DIRECTORY = Path(
    getattr(
        config,
        "CLYDE_DIRECTORY",
        r"C:\\Users\\Bitra\\Downloads\\deobf-bot-updated\\deobf-bot-updated\\tuff\\idk",
    )
)

CLYDE_MAIN = getattr(
    config,
    "CLYDE_MAIN",
    "cli.js",
)

GOOFYSCATOR_DIRECTORY = Path(
    getattr(
        config,
        "GOOFYSCATOR_DIRECTORY",
        r"C:\Users\Bitra\Downloads\deobf-bot-updated\deobf-bot-updated\goofyscator",
    )
)

GOOFYSCATOR_CLI = Path(
    getattr(
        config,
        "GOOFYSCATOR_CLI",
        GOOFYSCATOR_DIRECTORY / "src" / "cli.js",
    )
)


LURAPH15_ROOT = Path(
    getattr(
        config,
        "LURAPH15_ROOT",
        r"C:\Users\Bitra\Downloads\deobf-bot-updated\deobf-bot-updated\deobf_v14_7_v14_8_v14_9_full_fixed_v26",
    )
)

LURAPH14_CLI = Path(
    getattr(
        config,
        "LURAPH14_CLI",
        LURAPH15_ROOT / "cli.py",
    )
)

LURAPH15_CLI = Path(
    getattr(
        config,
        "LURAPH15_CLI",
        LURAPH15_ROOT / "deob.py",
    )
)

LURAPH15_PLUGIN = getattr(
    config,
    "LURAPH15_PLUGIN",
    "luraph_v15",
)

LURAPH147_PLUGIN = getattr(
    config,
    "LURAPH147_PLUGIN",
    "luraph_v14_7",
)

LURAPH148_PLUGIN = getattr(
    config,
    "LURAPH148_PLUGIN",
    "luraph_v14_8",
)

LURAPH149_PLUGIN = getattr(
    config,
    "LURAPH149_PLUGIN",
    "luraph_v14_9",
)

BYPASS_API_KEY = str(getattr(config, "BYPASS_API_KEY", "") or "").strip()
LOOTLABS_API_KEY = str(getattr(config, "LOOTLABS_API_KEY", "") or "").strip()
LURAPH_GATE_BYPASS_ROLE_IDS = {1551869514629517323}
BYPASS_PUBLISHER_ENDPOINT = str(
    getattr(
        config,
        "BYPASS_PUBLISHER_ENDPOINT",
        "https://kys.linkvertise.lol/api/v2/bck/publishers",
    )
    or "https://kys.linkvertise.lol/api/v2/bck/publishers"
).strip()


# ============================================================
# OXYGEN
# ============================================================

LUNE_PATH = BASE_DIR / "lune.exe"
L3_RUNNER = BASE_DIR / "run_l3.lua"
L2_SCRIPT = BASE_DIR / "l2.lua"

STATE_FILE = BASE_DIR / "radium_bot_state.json"

MAX_FILE_SIZE = 8 * 1024 * 1024
PROCESS_TIMEOUT = 180

ALLOWED_EXTENSIONS = {
    ".lua",
    ".luau",
    ".txt",
    ".md",
}


# ============================================================
# DEFAULT ROBLOX PROFILE
# ============================================================

DEFAULT_PROFILE = {
    "place_id": 1818,
    "game_id": 6767,
    "place_version": 1,

    "user_name": "Player",
    "display_name": "Player",
    "user_id": 1,

    "locale": "en-us",
    "membership_type": "None",

    "executor_name": "Madium",
    "nexomia_fingerprint": "",
}

EXECUTOR_NAMES = (
    "Volt",
    "Pottasium",
    "Potassium",
    "Madium",
    "Real",
    "Xeno",
    "JJsploit",
)

EXECUTOR_LOOKUP = {
    name.lower(): name
    for name in EXECUTOR_NAMES
}


def normalize_executor_name(value):
    if value is None:
        return None

    return EXECUTOR_LOOKUP.get(
        str(value).strip().lower()
    )


# ============================================================
# DISCORD
# ============================================================

intents = discord.Intents.default()
intents.message_content = True
intents.members = True

bot = commands.Bot(
    command_prefix=COMMAND_PREFIX,
    intents=intents,
    help_command=None,
)


# ============================================================
# EMBEDS
# ============================================================

def radium_embed(
    title,
    description=None,
    color=None,
):
    embed = discord.Embed(
        title=title,
        description=description,
        color=(
            color
            or discord.Color.from_rgb(
                87,
                255,
                170,
            )
        ),
    )

    embed.set_footer(
        text="Oxygen"
    )

    return embed


def deobf_embed(
    title,
    description=None,
    color=None,
):
    embed = discord.Embed(
        title=title,
        description=description,
        color=(
            color
            or discord.Color.from_rgb(
                88,
                101,
                242,
            )
        ),
    )

    embed.set_footer(
        text="Oxygen • Deobfuscator"
    )

    return embed


def trim(
    text,
    limit=1500,
):
    text = str(
        text or ""
    ).strip()

    if not text:
        return "No output."

    if len(text) > limit:
        return (
            text[:limit]
            + "\n..."
        )

    return text


# ============================================================
# PREMIUM
# ============================================================

def load_paid_users():
    if not PAID_USERS_FILE.exists():
        PAID_USERS_FILE.write_text(
            json.dumps(
                {
                    "users": []
                },
                indent=4,
            ),
            encoding="utf-8",
        )

        return set()

    try:
        data = json.loads(
            PAID_USERS_FILE.read_text(
                encoding="utf-8",
            )
        )

        return {
            int(user_id)
            for user_id
            in data.get(
                "users",
                [],
            )
        }

    except Exception as exc:
        print(
            f"[Premium] Failed to load users: {exc}"
        )

        return set()


def save_paid_users():
    PAID_USERS_FILE.write_text(
        json.dumps(
            {
                "users": sorted(
                    paid_users
                )
            },
            indent=4,
        ),
        encoding="utf-8",
    )


paid_users = load_paid_users()


async def is_staff(ctx: commands.Context):
    if ctx.guild is None:
        return False

    user = ctx.author

    # Server owner always bypasses
    if user.id == ctx.guild.owner_id:
        return True

    # Normal Member permission check
    permissions = getattr(
        user,
        "guild_permissions",
        None,
    )

    if (
        permissions is not None
        and permissions.administrator
    ):
        return True

    # Slash-command interaction permission data
    if ctx.interaction is not None:
        interaction_permissions = getattr(
            ctx.interaction,
            "permissions",
            None,
        )

        if (
            interaction_permissions is not None
            and interaction_permissions.administrator
        ):
            return True

    # Fallback: fetch fresh member data from Discord
    try:
        member = await ctx.guild.fetch_member(
            user.id
        )

        if member.guild_permissions.administrator:
            return True

    except (
        discord.NotFound,
        discord.Forbidden,
        discord.HTTPException,
    ):
        pass

    return False

def get_channel_category_id(channel):
    if isinstance(channel, discord.Thread):
        parent = channel.parent

        if parent is None:
            return None

        return getattr(
            parent,
            "category_id",
            None,
        )

    return getattr(
        channel,
        "category_id",
        None,
    )

async def is_premium_user(ctx: commands.Context):
    if await is_staff(ctx):
        return True

    return ctx.author.id in paid_users


def has_luraph_gate_bypass_role(member):
    return any(
        getattr(role, "id", None) in LURAPH_GATE_BYPASS_ROLE_IDS
        for role in getattr(member, "roles", ())
    )


def get_effective_channel_id(channel):
    if isinstance(channel, discord.Thread):
        parent = channel.parent
        return getattr(parent, "id", None)

    return getattr(channel, "id", None)


async def check_bot_access(
    ctx: commands.Context,
):
    if ctx.guild is None:
        await ctx.send(
            embed=deobf_embed(
                "Server Only",
                "This bot cannot be used in DMs.",
                discord.Color.red(),
            ),
            ephemeral=True,
        )
        return False

    guild_id = ctx.guild.id

    if guild_id == FREE_GUILD_ID:
        return True
    if guild_id == FREE_GUILD_ID2:
        return True

    if guild_id != PAID_GUILD_ID:
        await ctx.send(
            embed=deobf_embed(
                "Unavailable",
                "Oxygen is not enabled in this server.",
                discord.Color.red(),
            ),
            ephemeral=True,
        )
        return False

    channel_id = get_effective_channel_id(ctx.channel)
    category_id = get_channel_category_id(ctx.channel)
    premium = await is_premium_user(ctx)

    # In the paid server, this channel is available to everyone.
    if channel_id == DEOBF_CHANNEL_ID:
        return True

    # Premium users/staff may also use the paid deobfuscator category.
    if premium and category_id == PAID_CATEGORY_ID:
        return True

    if premium:
        location_text = (
            f"Use the bot in <#{DEOBF_CHANNEL_ID}> or inside "
            f"the premium category <#{PAID_CATEGORY_ID}>."
        )
    else:
        location_text = f"Use the bot in <#{DEOBF_CHANNEL_ID}>."

    await ctx.send(
        embed=deobf_embed(
            "Wrong Channel",
            location_text,
            discord.Color.orange(),
        ),
        ephemeral=True,
    )
    return False


# ============================================================
# PREMIUM ADMIN COMMANDS
# ============================================================

@bot.hybrid_command(
    name="premium_add",
    description="Give a user premium access.",
)
async def premium_add(
    ctx: commands.Context,
    member: discord.Member,
):
    if ctx.guild is None:
        return

    if not await is_staff(ctx):
        await ctx.send(
            embed=deobf_embed(
                "Permission Denied",
                "Administrator permission required.",
                discord.Color.red(),
            ),
            ephemeral=True,
        )

        return

    paid_users.add(
        member.id
    )

    save_paid_users()

    await ctx.send(
        embed=deobf_embed(
            "Premium Added",
            (
                f"{member.mention} now has "
                "paid access."
            ),
            discord.Color.green(),
        ),
        ephemeral=True,
    )


@bot.hybrid_command(
    name="premium_remove",
    description="Remove a user's premium access.",
)
async def premium_remove(
    ctx: commands.Context,
    member: discord.Member,
):
    if ctx.guild is None:
        return

    if not await is_staff(ctx):
        await ctx.send(
            embed=deobf_embed(
                "Permission Denied",
                "Administrator permission required.",
                discord.Color.red(),
            ),
            ephemeral=True,
        )

        return

    paid_users.discard(
        member.id
    )

    save_paid_users()

    await ctx.send(
        embed=deobf_embed(
            "Premium Removed",
            (
                f"{member.mention} no longer "
                "has paid access."
            ),
            discord.Color.orange(),
        ),
        ephemeral=True,
    )


@bot.hybrid_command(
    name="premium_check",
    description="Check a user's premium status.",
)
async def premium_check(
    ctx: commands.Context,
    member: discord.Member = None,
):
    if ctx.guild is None:
        return

    if not await is_staff(ctx):
        await ctx.send(
            embed=deobf_embed(
                "Permission Denied",
                "Administrator permission required.",
                discord.Color.red(),
            ),
            ephemeral=True,
        )

        return

    member = (
        member
        or ctx.author
    )

    active = (
        member.id
        in paid_users
    )

    await ctx.send(
        embed=deobf_embed(
            "Premium Status",
            (
                f"{member.mention}\n\n"
                f"Status: "
                f"`{'ACTIVE' if active else 'INACTIVE'}`"
            ),
            (
                discord.Color.green()
                if active
                else discord.Color.red()
            ),
        ),
        ephemeral=True,
    )


# ============================================================
# OXYGEN STATE
# ============================================================

def default_state():
    return {
        "users": {}
    }


def normalize_profile(
    value,
):
    profile = dict(
        DEFAULT_PROFILE
    )

    if isinstance(
        value,
        dict,
    ):
        for key in profile:
            if key in value:
                profile[key] = value[key]

    for key in (
        "place_id",
        "game_id",
        "place_version",
        "user_id",
    ):
        try:
            profile[key] = int(
                profile[key]
            )

        except Exception:
            profile[key] = (
                DEFAULT_PROFILE[key]
            )

    for key in (
        "user_name",
        "display_name",
        "locale",
        "membership_type",
        "executor_name",
        "nexomia_fingerprint",
    ):
        profile[key] = str(
            profile[key]
        )

    executor_name = normalize_executor_name(
        profile.get("executor_name")
    )

    profile["executor_name"] = (
        executor_name
        or DEFAULT_PROFILE["executor_name"]
    )

    return profile


def save_state(
    data,
):
    STATE_FILE.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    tmp = STATE_FILE.with_suffix(
        ".json.tmp"
    )

    tmp.write_text(
        json.dumps(
            data,
            indent=4,
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    os.replace(
        tmp,
        STATE_FILE,
    )


def load_state():
    if not STATE_FILE.exists():
        data = default_state()

        save_state(
            data
        )

        return data

    try:
        data = json.loads(
            STATE_FILE.read_text(
                encoding="utf-8"
            )
        )

        if not isinstance(
            data,
            dict,
        ):
            return default_state()

        users = data.get(
            "users",
            {},
        )

        result = {
            "users": {}
        }

        if isinstance(
            users,
            dict,
        ):
            for uid, profile in users.items():
                result["users"][str(uid)] = normalize_profile(
                    profile
                )

        return result

    except Exception as exc:
        print(
            f"[State] {exc}"
        )

        return default_state()


state = load_state()


def get_profile(
    user_id,
):
    uid = str(
        user_id
    )

    if uid not in state["users"]:
        state["users"][uid] = dict(
            DEFAULT_PROFILE
        )

        save_state(
            state
        )

    return normalize_profile(
        state["users"][uid]
    )


def update_profile(
    user_id,
    updates,
):
    profile = get_profile(
        user_id
    )

    for key, value in updates.items():
        if value is not None:
            profile[key] = value

    profile = normalize_profile(
        profile
    )

    state["users"][
        str(user_id)
    ] = profile

    save_state(
        state
    )

    return profile


def profile_summary(
    profile,
):
    return (
        f"**Place ID:** `{profile['place_id']}`\n"
        f"**Game ID:** `{profile['game_id']}`\n"
        f"**Place Version:** `{profile['place_version']}`\n\n"

        f"**Username:** `{profile['user_name']}`\n"
        f"**Display Name:** `{profile['display_name']}`\n"
        f"**User ID:** `{profile['user_id']}`\n\n"

        f"**Locale:** `{profile['locale']}`\n"
        f"**Membership:** `{profile['membership_type']}`\n\n"

        f"**Executor:** `{profile['executor_name']}`\n"
        f"**Nexomia Fingerprint:** "
        f"`{profile.get('nexomia_fingerprint') or 'not set'}`"
    )


# ============================================================
# FILE / INPUT HELPERS
# ============================================================

def clean_filename(
    filename,
):
    filename = Path(
        filename or "input.lua"
    ).name

    return re.sub(
        r"[^A-Za-z0-9._-]",
        "_",
        filename,
    )


CODEBLOCK_RE = re.compile(
    r"^```(?:lua|luau|txt)?\s*\n?(.*?)\n?```$",
    re.IGNORECASE | re.DOTALL,
)


def strip_codeblock(
    text,
):
    text = (
        text
        or ""
    ).strip()

    match = CODEBLOCK_RE.match(
        text
    )

    if match:
        return match.group(
            1
        ).strip()

    return text


class DeobfuscationOutputError(RuntimeError):
    pass


def _lua_validation_view(source):
    """Return Lua with comments/strings masked while preserving token boundaries."""
    text = str(source or "")
    out = []
    i = 0
    n = len(text)
    unterminated = None

    def long_bracket_at(index):
        if index >= n or text[index] != "[":
            return None
        j = index + 1
        while j < n and text[j] == "=":
            j += 1
        if j < n and text[j] == "[":
            return j - index - 1
        return None

    while i < n:
        ch = text[i]

        if ch == "-" and i + 1 < n and text[i + 1] == "-":
            eqs = long_bracket_at(i + 2)
            if eqs is not None:
                close = "]" + ("=" * eqs) + "]"
                start = i + 3 + eqs
                end = text.find(close, start)
                if end == -1:
                    unterminated = "long comment"
                    out.append(" ")
                    break
                segment = text[i:end + len(close)]
                out.extend("\n" if c == "\n" else " " for c in segment)
                i = end + len(close)
                continue

            end = text.find("\n", i + 2)
            if end == -1:
                out.extend(" " for _ in text[i:])
                break
            out.extend(" " for _ in text[i:end])
            out.append("\n")
            i = end + 1
            continue

        if ch in ("'", '"'):
            quote = ch
            out.append(" ")
            i += 1
            escaped = False
            closed = False
            while i < n:
                c = text[i]
                out.append("\n" if c == "\n" else " ")
                i += 1
                if escaped:
                    escaped = False
                    continue
                if c == "\\":
                    escaped = True
                    continue
                if c == quote:
                    closed = True
                    break
            if not closed:
                unterminated = "string"
                break
            continue

        eqs = long_bracket_at(i)
        if eqs is not None:
            close = "]" + ("=" * eqs) + "]"
            start = i + 2 + eqs
            end = text.find(close, start)
            if end == -1:
                unterminated = "long string"
                out.append(" ")
                break
            segment = text[i:end + len(close)]
            out.extend("\n" if c == "\n" else " " for c in segment)
            i = end + len(close)
            continue

        out.append(ch)
        i += 1

    return "".join(out), unterminated


def validate_deobfuscated_output(result):
    if not isinstance(result, str):
        raise DeobfuscationOutputError("Backend returned a non-text result.")

    if not result.strip():
        raise DeobfuscationOutputError("Backend returned an empty result.")

    masked, unterminated = _lua_validation_view(result)
    code = masked.strip()

    if unterminated:
        raise DeobfuscationOutputError(
            f"Backend output appears incomplete: unterminated {unterminated}."
        )

    # Comments and string contents do not count as Lua code for this guard.
    meaningful = re.sub(r"[\s;]+", "", code)
    if not meaningful:
        raise DeobfuscationOutputError(
            "Backend output contains no Lua code after comments are ignored."
        )

    # Catch the most common truncation mode without requiring a Lua/Luau runtime.
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for ch in masked:
        if ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            if not stack or stack[-1] != pairs[ch]:
                raise DeobfuscationOutputError(
                    f"Backend output appears incomplete/invalid: unexpected `{ch}`."
                )
            stack.pop()

    if stack:
        raise DeobfuscationOutputError(
            "Backend output appears incomplete: unclosed bracket/parenthesis/table literal."
        )

    # Lightweight Lua block validation. `for`/`while` consume their following `do`
    # rather than counting it as a second block.
    tokens = re.findall(
        r"\b(?:function|if|for|while|do|repeat|end|until)\b",
        masked,
        flags=re.IGNORECASE,
    )
    blocks = []
    pending_loop_do = 0
    for token in (t.lower() for t in tokens):
        if token == "function":
            blocks.append("function")
        elif token == "if":
            blocks.append("if")
        elif token in ("for", "while"):
            blocks.append(token)
            pending_loop_do += 1
        elif token == "do":
            if pending_loop_do:
                pending_loop_do -= 1
            else:
                blocks.append("do")
        elif token == "repeat":
            blocks.append("repeat")
        elif token == "until":
            if not blocks or blocks[-1] != "repeat":
                raise DeobfuscationOutputError(
                    "Backend output appears incomplete/invalid: unmatched `until`."
                )
            blocks.pop()
        elif token == "end":
            if not blocks or blocks[-1] == "repeat":
                raise DeobfuscationOutputError(
                    "Backend output appears incomplete/invalid: unmatched `end`."
                )
            blocks.pop()

    if blocks or pending_loop_do:
        raise DeobfuscationOutputError(
            "Backend output appears incomplete: one or more Lua blocks were not closed."
        )

    # Require executable/declarative Lua structure, not just random text/numbers.
    lua_like = any((
        re.search(r"\b(?:local|function|return|if|for|while|repeat|do|break|continue)\b", masked, re.I),
        re.search(r"\b[A-Za-z_]\w*\s*=", masked),
        re.search(r"\b[A-Za-z_]\w*(?:\.[A-Za-z_]\w*|:[A-Za-z_]\w*)*\s*\(", masked),
        re.search(r"\b(?:game|workspace|script)\s*[\.:\[]", masked, re.I),
    ))
    if not lua_like:
        raise DeobfuscationOutputError(
            "Backend output does not appear to contain executable Lua code."
        )

    return result


async def get_replied_message(
    ctx,
):
    if not ctx.message:
        return None

    reference = ctx.message.reference

    if not reference:
        return None

    if (
        reference.resolved
        and isinstance(
            reference.resolved,
            discord.Message,
        )
    ):
        return reference.resolved

    if not reference.message_id:
        return None

    try:
        return await ctx.channel.fetch_message(
            reference.message_id
        )

    except discord.HTTPException:
        return None


async def download_attachment(
    attachment,
):
    if attachment.size > MAX_FILE_SIZE:
        raise ValueError(
            "File is too large."
        )

    extension = Path(
        attachment.filename
    ).suffix.lower()

    if (
        extension
        not in ALLOWED_EXTENSIONS
    ):
        raise ValueError(
            "File must be .lua, .luau, .txt, or .md"
        )

    data = await attachment.read()

    if len(data) > MAX_FILE_SIZE:
        raise ValueError(
            "File is too large."
        )

    return data.decode(
        "utf-8",
        errors="replace",
    )


async def download_url(
    url,
):
    timeout = aiohttp.ClientTimeout(
        total=25
    )

    async with aiohttp.ClientSession(
        timeout=timeout
    ) as session:

        async with session.get(
            url,
            allow_redirects=True,
        ) as response:

            if response.status != 200:
                raise ValueError(
                    f"URL returned HTTP {response.status}"
                )

            data = await response.content.read(
                MAX_FILE_SIZE + 1
            )

            if len(data) > MAX_FILE_SIZE:
                raise ValueError(
                    "Downloaded file is too large."
                )

            return data.decode(
                "utf-8",
                errors="replace",
            )


def _direct_url_from_text(value):
    value = strip_codeblock(str(value or "")).strip()

    if re.fullmatch(
        r"https?://[^\\s<>`]+",
        value,
        re.IGNORECASE,
    ):
        return value.rstrip(".,);]}>\\\"'")

    return None


async def _resolve_text_script_input(value):
    value = str(value or "").strip()

    if not value:
        raise ValueError("Input is empty.")

    direct_url = _direct_url_from_text(value)

    if direct_url:
        if is_deobfuscation_blacklisted(direct_url):
            raise ValueError("This source is excluded from deobfuscation.")

        code = await download_url(direct_url)

        if is_deobfuscation_blacklisted(code):
            raise ValueError("This source is excluded from deobfuscation.")

        return code, "input.lua"

    code = strip_codeblock(value)

    if not code.strip():
        raise ValueError("Input is empty.")

    return code, "input.lua"


async def resolve_script_input(
    ctx,
    attachment=None,
    source=None,
):
    """
    Resolve script input consistently for both prefix and slash commands.

    Priority:
      1. Explicit slash attachment
      2. Attachment on the command message
      3. Explicit raw/codeblock/URL source
      4. Replied attachment
      5. Replied raw/codeblock/URL text
    """

    if attachment is not None:
        code = await download_attachment(attachment)
        return code, clean_filename(attachment.filename)

    if ctx.message and ctx.message.attachments:
        file = ctx.message.attachments[0]
        code = await download_attachment(file)
        return code, clean_filename(file.filename)

    if source and str(source).strip():
        return await _resolve_text_script_input(source)

    replied = await get_replied_message(ctx)

    if replied:
        if replied.attachments:
            file = replied.attachments[0]
            code = await download_attachment(file)
            return code, clean_filename(file.filename)

        if replied.content and replied.content.strip():
            return await _resolve_text_script_input(replied.content)

    raise ValueError(
        "Upload a file, give a URL/code/codeblock, or reply to a script."
    )


# ============================================================
# REACTIONS
# ============================================================

async def add_reaction(
    message,
    emoji,
):
    if not message:
        return

    try:
        await message.add_reaction(
            emoji
        )

    except Exception:
        pass


async def remove_reaction(
    message,
    emoji,
):
    if not message:
        return

    try:
        await message.remove_reaction(
            emoji,
            bot.user,
        )

    except Exception:
        pass


# ============================================================
# TEXT ENCODING
# ============================================================

def read_backend_text(path):
    """Read generated Lua as UTF-8, with latin-1 only as a legacy fallback."""
    data = Path(path).read_bytes()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return data.decode("latin-1")


# ============================================================
# PROCESS
# ============================================================

async def run_process(
    args,
    *,
    cwd=None,
    env=None,
    timeout=PROCESS_TIMEOUT,
):
    process = await asyncio.create_subprocess_exec(
        *args,

        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,

        cwd=(
            str(cwd)
            if cwd
            else None
        ),

        env=env,
    )

    try:
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=timeout,
        )

    except asyncio.TimeoutError:
        process.kill()

        try:
            await process.communicate()
        except Exception:
            pass

        raise TimeoutError(
            f"Process timed out after {timeout} seconds."
        )

    return (
        process.returncode,

        stdout.decode(
            "utf-8",
            errors="replace",
        ),

        stderr.decode(
            "utf-8",
            errors="replace",
        ),
    )


def heavy_backend_timeout(source):
    """Give large VM deobfuscation jobs enough time without making small jobs slow."""
    size_mb = max(1, (len(source.encode("utf-8", errors="ignore")) + 999_999) // 1_000_000)
    return max(DEOBF_TIMEOUT, min(900, 180 + size_mb * 90))


# ============================================================
# IB1
# ============================================================

async def run_ib1(
    source,
):
    # Use the unified deob.py backend with the IronBrew1 plugin.
    if not LURAPH15_ROOT.exists():
        raise FileNotFoundError(
            f"Deobfuscator directory is missing: {LURAPH15_ROOT}"
        )

    if not LURAPH15_CLI.exists():
        raise FileNotFoundError(
            f"Deobfuscator CLI is missing: {LURAPH15_CLI}"
        )

    with tempfile.TemporaryDirectory(
        prefix="ironbrew1_"
    ) as temp_dir:
        temp = Path(temp_dir)
        input_path = temp / "input.lua"
        output_path = temp / "deobfuscated.lua"

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="strict",
        )

        returncode, stdout, stderr = await run_process(
            [
                sys.executable,
                str(LURAPH15_CLI),
                str(input_path),
                "-o",
                str(output_path),
                "--obfuscator",
                "ironbrew1",
                "--timeout",
                str(max(120, heavy_backend_timeout(source) // 3)),
            ],
            cwd=LURAPH15_ROOT,
            timeout=heavy_backend_timeout(source),
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or (
                    "IronBrew 1 backend exited with "
                    f"code {returncode}"
                )
            )

        if not output_path.exists():
            raise RuntimeError(
                (
                    "IronBrew 1 backend completed but did not "
                    "create the output file.\n\n"
                    f"Expected: {output_path}\n\n"
                    f"STDOUT:\n{stdout}\n\n"
                    f"STDERR:\n{stderr}"
                )
            )

        return read_backend_text(output_path)


# ============================================================
# IB2 / AZTUPBREW
# ============================================================

async def run_ib2(
    source,
):
    if not IB2_CLI_PATH.exists():
        raise FileNotFoundError(
            f"Missing IB2 CLI: {IB2_CLI_PATH}"
        )

    if not IB2_ROOT.exists():
        raise FileNotFoundError(
            f"Missing IB2 root: {IB2_ROOT}"
        )

    luajit = (
        IB2_ROOT
        / "util"
        / "luajit.exe"
    )

    if not luajit.exists():
        raise FileNotFoundError(
            (
                "IB2 runtime is incomplete. "
                f"Missing: {luajit}"
            )
        )

    tasks_dir = (
        IB2_ROOT
        / "tasks"
    )

    with tempfile.TemporaryDirectory(
        prefix="ib2_"
    ) as temp_dir:

        temp = Path(
            temp_dir
        )

        input_path = (
            temp
            / (
                "radium_"
                + uuid.uuid4().hex[:12]
                + ".lua"
            )
        )

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="replace",
        )

        old_outputs = {}

        if tasks_dir.exists():
            for output in tasks_dir.rglob(
                "deobfuscated.lua"
            ):
                try:
                    old_outputs[
                        output.resolve()
                    ] = (
                        output.stat().st_mtime_ns
                    )

                except OSError:
                    pass

        returncode, stdout, stderr = await run_process(
            [
                str(IB2_CLI_PATH),
                str(input_path),
            ],
            cwd=IB2_ROOT,
            timeout=DEOBF_TIMEOUT,
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or (
                    "IB2 CLI exited with "
                    f"code {returncode}"
                )
            )

        candidates = []

        if tasks_dir.exists():
            for output in tasks_dir.rglob(
                "deobfuscated.lua"
            ):
                try:
                    old_time = old_outputs.get(
                        output.resolve()
                    )

                    new_time = (
                        output.stat().st_mtime_ns
                    )

                    if (
                        old_time is None
                        or new_time != old_time
                    ):
                        candidates.append(
                            output
                        )

                except OSError:
                    pass

        candidates.sort(
            key=lambda p:
                p.stat().st_mtime_ns,
            reverse=True,
        )

        if not candidates:
            raise RuntimeError(
                (
                    "IB2 finished but no new "
                    "deobfuscated.lua was produced.\n\n"
                    f"STDOUT:\n{stdout}\n\n"
                    f"STDERR:\n{stderr}"
                )
            )

        return candidates[0].read_text(
            encoding="utf-8",
            errors="replace",
        )


# ============================================================
# IB3
# ============================================================

async def run_ib3(
    source,
):
    try:
        from deobfuscator import (
            parse_ib3,
            find_root,
        )

    except Exception as exc:
        raise RuntimeError(
            (
                "IB3 backend could not be imported: "
                f"{exc}"
            )
        )

    parsed = await asyncio.to_thread(
        parse_ib3,
        source,
    )

    root = find_root(
        parsed.prototypes
    )

    lines = [
        "-- IronBrew 3 decoded VM output",
        f"-- profile: {parsed.profile}",
        f"-- constants: {len(parsed.constants)}",
        f"-- prototypes: {len(parsed.prototypes)}",
        "",
    ]

    for index, prototype in enumerate(
        parsed.prototypes
    ):
        lines.append(
            (
                f"local function fn_{index}(...)"
            )
        )

        for pc, instruction in enumerate(
            prototype.instructions,
            1,
        ):
            lines.append(
                (
                    f"    -- [{pc}] "
                    f"opcode={instruction.opcode} "
                    f"a={getattr(instruction, 'a', None)} "
                    f"b={getattr(instruction, 'b', None)} "
                    f"c={getattr(instruction, 'c', None)} "
                    f"jump={getattr(instruction, 'jump', None)}"
                )
            )

        lines.append(
            "end"
        )

        lines.append(
            ""
        )

    lines.append(
        f"return fn_{root}(...)"
    )

    return "\n".join(
        lines
    )


# ============================================================
# LUAOBFUSCATOR
# ============================================================

async def run_luaobfuscator(
    source,
):
    main_file = (
        LUAOBF_DIRECTORY
        / LUAOBF_MAIN
    )

    if not main_file.exists():
        raise FileNotFoundError(
            (
                "LuaObfuscator backend is missing: "
                f"{main_file}"
            )
        )

    output_dir = (
        LUAOBF_DIRECTORY
        / "output"
    )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    job_id = uuid.uuid4().hex[:12]

    output_path = (
        output_dir
        / f"{job_id}.lua"
    )

    with tempfile.TemporaryDirectory(
        prefix="luaobf_"
    ) as temp_dir:

        temp = Path(
            temp_dir
        )

        input_path = (
            temp
            / f"{job_id}.lua"
        )

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="replace",
        )

        try:
            returncode, stdout, stderr = await run_process(
                [
                    "node",
                    str(main_file),
                    str(input_path),
                    "--out",
                    str(output_path),
                ],
                cwd=LUAOBF_DIRECTORY,
                timeout=DEOBF_TIMEOUT,
            )

            if returncode != 0:
                raise RuntimeError(
                    stderr.strip()
                    or stdout.strip()
                    or (
                        "LuaObfuscator backend "
                        f"exited with {returncode}"
                    )
                )

            if not output_path.exists():
                raise RuntimeError(
                    (
                        "LuaObfuscator backend finished "
                        "but did not create the output file.\n\n"
                        f"Expected: {output_path}\n\n"
                        f"STDOUT:\n{stdout}\n\n"
                        f"STDERR:\n{stderr}"
                    )
                )

            return output_path.read_text(
                encoding="utf-8",
                errors="replace",
            )

        finally:
            try:
                output_path.unlink(
                    missing_ok=True
                )
            except Exception:
                pass


# ============================================================
# PROMETHEUS
# ============================================================

async def run_prometheus(
    source,
):
    main_file = PROMETHEUS_DIRECTORY / PROMETHEUS_MAIN

    if not main_file.exists():
        raise FileNotFoundError(
            f"Prometheus backend is missing: {main_file}"
        )

    with tempfile.TemporaryDirectory(
        prefix="prometheus_"
    ) as temp_dir:
        temp = Path(temp_dir)
        input_path = temp / "script.lua"
        output_path = temp / "out.lua"

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="replace",
        )

        returncode, stdout, stderr = await run_process(
            [
                "node",
                str(main_file),
                str(input_path),
                "-o",
                str(output_path),
            ],
            cwd=PROMETHEUS_DIRECTORY,
            timeout=DEOBF_TIMEOUT,
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or f"Prometheus exited with code {returncode}"
            )

        if not output_path.exists():
            raise RuntimeError(
                "Prometheus completed but out.lua was not created.\n\n"
                f"STDOUT:\n{stdout}\n\nSTDERR:\n{stderr}"
            )

        return output_path.read_text(
            encoding="utf-8",
            errors="replace",
        )


# ============================================================
# CLYDE
# ============================================================

async def run_clyde(source):
    with tempfile.TemporaryDirectory(prefix="clyde_") as temp_dir:
        temp = Path(temp_dir)

        input_path = temp / "obfuscated.lua"
        output_path = temp / "clean.lua"
        ir_path = temp / "vm_ir.txt"

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="replace",
        )

        returncode, stdout, stderr = await run_process(
            [
                "clyde-deobf",
                str(input_path),
                "-o",
                str(output_path),
                "--ir",
                str(ir_path),
            ],
            cwd=temp,
            timeout=DEOBF_TIMEOUT,
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or f"Clyde deobfuscator exited with code {returncode}"
            )

        if not output_path.exists():
            raise RuntimeError(
                "Clyde deobfuscator completed but clean.lua was not created.\n\n"
                f"STDOUT:\n{stdout}\n\n"
                f"STDERR:\n{stderr}"
            )

        return output_path.read_text(
            encoding="utf-8",
            errors="replace",
        )


# ============================================================
# GOOFYSCATOR
# ============================================================

async def run_goofyscator(
    source,
):
    if not GOOFYSCATOR_DIRECTORY.exists():
        raise FileNotFoundError(
            f"Goofyscator directory is missing: {GOOFYSCATOR_DIRECTORY}"
        )

    if not GOOFYSCATOR_CLI.exists():
        raise FileNotFoundError(
            f"Goofyscator CLI is missing: {GOOFYSCATOR_CLI}"
        )

    with tempfile.TemporaryDirectory(
        prefix="goofyscator_"
    ) as temp_dir:
        temp = Path(temp_dir)

        input_path = temp / "input.lua"
        output_path = temp / "deobfuscated.lua"

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="replace",
        )

        returncode, stdout, stderr = await run_process(
            [
                "node",
                str(GOOFYSCATOR_CLI),
                str(input_path),
                "-o",
                str(output_path),
            ],
            cwd=GOOFYSCATOR_DIRECTORY,
            timeout=DEOBF_TIMEOUT,
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or (
                    "Goofyscator exited with "
                    f"code {returncode}"
                )
            )

        if not output_path.exists():
            raise RuntimeError(
                (
                    "Goofyscator completed but "
                    "deobfuscated.lua was not created.\n\n"
                    f"STDOUT:\n{stdout}\n\n"
                    f"STDERR:\n{stderr}"
                )
            )

        return output_path.read_text(
            encoding="latin1",
            errors="replace",
        )


# ============================================================
# LURAPH v14.7 / v14.8 / v14.9 / v15
# ============================================================

async def run_luraph_backend(
    source,
    *,
    plugin,
    display_name,
    temp_prefix,
):
    if not LURAPH15_ROOT.exists():
        raise FileNotFoundError(
            f"{display_name} backend directory is missing: {LURAPH15_ROOT}"
        )

    v14_engines = {
        "luraph_v14_7": "14.7",
        "luraph_v14_8": "14.8",
        "luraph_v14_9": "14.9",
    }
    engine = v14_engines.get(str(plugin))
    cli_path = LURAPH14_CLI if engine else LURAPH15_CLI

    if not cli_path.exists():
        raise FileNotFoundError(
            f"{display_name} deobfuscator is missing: {cli_path}"
        )

    with tempfile.TemporaryDirectory(
        prefix=temp_prefix
    ) as temp_dir:
        temp = Path(temp_dir)
        input_path = temp / "input.lua"
        output_path = temp / "deobfuscated.lua"

        input_path.write_text(
            source,
            encoding="utf-8",
            errors="strict",
        )

        timeout = heavy_backend_timeout(source)

        if engine:
            command = [
                sys.executable,
                str(cli_path),
                str(input_path),
                "-o",
                str(output_path),
                "--engine",
                engine,
                "--timeout",
                str(max(120, timeout // 3)),
            ]
        else:
            command = [
                sys.executable,
                str(cli_path),
                str(input_path),
                "-o",
                str(output_path),
                "--obfuscator",
                str(plugin),
                "--timeout",
                str(max(120, timeout // 3)),
            ]

        returncode, stdout, stderr = await run_process(
            command,
            cwd=LURAPH15_ROOT,
            timeout=timeout,
        )

        if returncode != 0:
            raise RuntimeError(
                stderr.strip()
                or stdout.strip()
                or (
                    f"{display_name} backend exited with "
                    f"code {returncode}"
                )
            )

        if not output_path.exists():
            raise RuntimeError(
                (
                    f"{display_name} backend completed but did not "
                    "create the output file.\n\n"
                    f"Expected: {output_path}\n\n"
                    f"STDOUT:\n{stdout}\n\n"
                    f"STDERR:\n{stderr}"
                )
            )

        return read_backend_text(output_path)


async def run_luraph147(source):
    return await run_luraph_backend(
        source,
        plugin=LURAPH147_PLUGIN,
        display_name="Luraph v14.7",
        temp_prefix="luraph147_",
    )


async def run_luraph148(source):
    return await run_luraph_backend(
        source,
        plugin=LURAPH148_PLUGIN,
        display_name="Luraph v14.8",
        temp_prefix="luraph148_",
    )


async def run_luraph149(source):
    return await run_luraph_backend(
        source,
        plugin=LURAPH149_PLUGIN,
        display_name="Luraph v14.9",
        temp_prefix="luraph149_",
    )


async def run_luraph15(source):
    return await run_luraph_backend(
        source,
        plugin=LURAPH15_PLUGIN,
        display_name="Luraph v15",
        temp_prefix="luraph15_",
    )


# ============================================================
# DETECTION
# ============================================================

def detect_obfuscator(
    source,
):
    lower = source.lower()

    if (
        "--ironbrew3" in lower
        or "ironbrew3:" in lower
    ):
        return (
            "ib3",
            "IronBrew 3",
            0.99,
        )

    if (
        "aztupbrew" in lower
    ):
        return (
            "ib2",
            "AztupBrew",
            0.99,
        )

    if (
        "ironbrew" in lower
    ):
        return (
            "ib2",
            "IronBrew",
            0.85,
        )

    if (
        "luaobfuscator" in lower
    ):
        return (
            "luaobfuscator",
            "LuaObfuscator",
            0.95,
        )

    if (
        "wynfuscate" in lower
    ):
        return (
            "unsupported",
            "wYnFuscate",
            0.99,
        )

    if (
        "moonsec" in lower
    ):
        return (
            "unsupported",
            "MoonSec",
            0.95,
        )

    if "luraph" in lower:
        if (
            "v14.9" in lower
            or "14.9" in lower
        ):
            return (
                "luraph149",
                "Luraph v14.9",
                0.99,
            )

        if (
            "v14.8" in lower
            or "14.8" in lower
        ):
            return (
                "luraph148",
                "Luraph v14.8",
                0.99,
            )

        if (
            "v14.7" in lower
            or "14.7" in lower
        ):
            return (
                "luraph147",
                "Luraph v14.7",
                0.99,
            )

        if (
            "v15" in lower
            or "luraph obfuscator v15" in lower
            or "luraph v15" in lower
        ):
            return (
                "luraph15",
                "Luraph v15",
                0.99,
            )

        return (
            "luraph15",
            "Luraph",
            0.70,
        )

    if "lph_" in lower:
        return (
            "luraph15",
            "Luraph candidate",
            0.60,
        )

    if (
        "string.byte" in lower
        and "return(function" in lower
        and "math.floor" in lower
    ):
        return (
            "ib1",
            "IronBrew 1 candidate",
            0.55,
        )

    raise RuntimeError(
        "Could not confidently detect the obfuscator."
    )


async def run_selected_deobfuscator(
    backend,
    source,
):
    confidence = 1.0

    if backend == "auto":
        (
            backend,
            detected,
            confidence,
        ) = detect_obfuscator(
            source
        )

        if backend == "unsupported":
            raise RuntimeError(
                (
                    f"Detected {detected}, but "
                    "automatic support is not available yet."
                )
            )

    else:
        names = {
            "ib1": "IronBrew 1",
            "ib2": "IronBrew 2 / AztupBrew",
            "ib3": "IronBrew 3",
            "luaobfuscator": "LuaObfuscator",
            "prometheus": "Prometheus",
            "clyde": "Clyde",
            "goofyscator": "Goofyscator",
            "luraph147": "Luraph v14.7",
            "luraph148": "Luraph v14.8",
            "luraph149": "Luraph v14.9",
            "luraph15": "Luraph v15",
        }

        detected = names.get(
            backend,
            backend,
        )

    if backend == "ib1":
        result = await run_ib1(
            source
        )

    elif backend == "ib2":
        result = await run_ib2(
            source
        )

    elif backend == "ib3":
        result = await run_ib3(
            source
        )

    elif backend == "luaobfuscator":
        result = await run_luaobfuscator(
            source
        )

    elif backend == "prometheus":
        result = await run_prometheus(
            source
        )

    elif backend == "clyde":
        result = await run_clyde(
            source
        )

    elif backend == "goofyscator":
        result = await run_goofyscator(
            source
        )

    elif backend == "luraph147":
        result = await run_luraph147(
            source
        )

    elif backend == "luraph148":
        result = await run_luraph148(
            source
        )

    elif backend == "luraph149":
        result = await run_luraph149(
            source
        )

    elif backend == "luraph15":
        result = await run_luraph15(
            source
        )

    else:
        raise RuntimeError(
            f"Unknown backend: {backend}"
        )

    return (
        result,
        detected,
        backend,
        confidence,
    )


# ============================================================
# DEOBFUSCATOR UI
# ============================================================

BACKEND_NAMES = {
    "auto": "Auto-Detect",
    "ib1": "IronBrew 1",
    "ib2": "IronBrew 2 / AztupBrew",
    "ib3": "IronBrew 3",
    "luaobfuscator": "LuaObfuscator",
    "prometheus": "Prometheus",
    "clyde": "Clyde",
    "goofyscator": "Goofyscator",
    "luraph147": "Luraph v14.7",
    "luraph148": "Luraph v14.8",
    "luraph149": "Luraph v14.9",
    "luraph15": "Luraph v15",
}

FREE_BACKENDS = (
    "prometheus",
    "clyde",
    "goofyscator",
    "luaobfuscator",
    "ib1",
    "ib2",
    "luraph147",
    "luraph148",
    "luraph149",
    "luraph15",
)

PREMIUM_BACKENDS = (
    "auto",
    "prometheus",
    "clyde",
    "goofyscator",
    "ib1",
    "ib2",
    "ib3",
    "luaobfuscator",
    "luraph147",
    "luraph148",
    "luraph149",
    "luraph15",
)


LURAPH_EMOJI = discord.PartialEmoji(
    name="luraph",
    id=1553754695766646805,
)

# Luraph v14.x is available directly and does not use the LootLabs gate.
LURAPH_V14_DOWN = set()


def make_backend_options(premium):
    allowed = PREMIUM_BACKENDS if premium else FREE_BACKENDS
    emojis = {
        "auto": "🔎",
        "prometheus": "⚡",
        "clyde": "🧹",
        "goofyscator": "🤡",
        "luraph147": LURAPH_EMOJI,
        "luraph148": LURAPH_EMOJI,
        "luraph149": LURAPH_EMOJI,
        "luraph15": LURAPH_EMOJI,
    }

    return [
        discord.SelectOption(
            label=BACKEND_NAMES[backend],
            value=backend,
            emoji=emojis.get(backend),
            default=(backend == allowed[0]),
        )
        for backend in allowed
    ]


class BackendSelect(
    discord.ui.Select
):
    def __init__(
        self,
        premium,
    ):
        super().__init__(
            placeholder="Select deobfuscator",
            min_values=1,
            max_values=1,
            options=make_backend_options(premium),
        )

    async def callback(
        self,
        interaction,
    ):
        if interaction.user.id != self.view.owner_id:
            await interaction.response.send_message(
                "This menu is not yours.",
                ephemeral=True,
            )
            return

        selected = self.values[0]

        if selected not in self.view.allowed_backends:
            await interaction.response.send_message(
                "That backend is not available for your account.",
                ephemeral=True,
            )
            return

        self.view.backend = selected

        await interaction.response.edit_message(
            embed=self.view.make_embed(),
            view=self.view,
        )


class DeobfuscateButton(
    discord.ui.Button
):
    def __init__(
        self,
    ):
        super().__init__(
            label="Deobfuscate",
            emoji="▶️",
            style=discord.ButtonStyle.primary,
        )

    async def callback(
        self,
        interaction,
    ):
        if (
            interaction.user.id
            != self.view.owner_id
        ):
            await interaction.response.send_message(
                "This menu is not yours.",
                ephemeral=True,
            )

            return

        await interaction.response.defer()

        if not self.view.future.done():
            self.view.future.set_result(
                self.view.backend
            )

        self.view.stop()


class CancelButton(
    discord.ui.Button
):
    def __init__(
        self,
    ):
        super().__init__(
            label="Cancel",
            emoji="✖️",
            style=discord.ButtonStyle.secondary,
        )

    async def callback(
        self,
        interaction,
    ):
        if (
            interaction.user.id
            != self.view.owner_id
        ):
            await interaction.response.send_message(
                "This menu is not yours.",
                ephemeral=True,
            )

            return

        if not self.view.future.done():
            self.view.future.set_result(
                None
            )

        await interaction.response.edit_message(
            embed=deobf_embed(
                "Cancelled",
                "Deobfuscation cancelled.",
                discord.Color.dark_grey(),
            ),
            view=None,
        )

        self.view.stop()


class DeobfuscatorView(
    discord.ui.View
):
    def __init__(
        self,
        owner_id,
        filename,
        premium,
    ):
        super().__init__(
            timeout=120
        )

        self.owner_id = owner_id
        self.filename = filename
        self.premium = premium
        self.allowed_backends = (
            PREMIUM_BACKENDS
            if premium
            else FREE_BACKENDS
        )
        self.backend = self.allowed_backends[0]

        self.future = (
            asyncio
            .get_running_loop()
            .create_future()
        )

        self.add_item(
            BackendSelect(premium)
        )

        self.add_item(
            DeobfuscateButton()
        )

        self.add_item(
            CancelButton()
        )

    def make_embed(
        self,
    ):
        embed = deobf_embed(
            "Oxygen Deobfuscator",
            (
                f"Input: `{self.filename}`\n\n"
                f"Backend: "
                f"`{BACKEND_NAMES[self.backend]}`"
            ),
        )

        embed.add_field(
            name="Access",
            value=(
                "💎 Premium backends"
                if self.premium
                else "🆓 Free backends: Prometheus • Clyde • Goofyscator • LuaObfuscator • IronBrew 1 • IronBrew 2 • Luraph v14.7 • Luraph v14.8 • Luraph v14.9 • Luraph v15"
            ),
            inline=False,
        )

        embed.add_field(
            name="Accepted Input",
            value=(
                "File • URL • reply • "
                "codeblock • raw Lua"
            ),
            inline=False,
        )

        return embed

    async def on_timeout(
        self,
    ):
        if not self.future.done():
            self.future.set_result(
                None
            )


def manual_failure_embed(
    backend,
    error,
):
    embed = deobf_embed(
        "Deobfuscation Failed",
        (
            f"Backend: **{backend}**\n\n"
            "Automatic processing failed."
        ),
        discord.Color.red(),
    )

    embed.add_field(
        name="Error",
        value=(
            "```text\n"
            f"{trim(error, 1000)}"
            "\n```"
        ),
        inline=False,
    )

    embed.add_field(
        name="Manual Deobfuscation",
        value=(
            f"Upload the original obfuscated file "
            f"in <#{MANUAL_DEOBF_CHANNEL_ID}>."
        ),
        inline=False,
    )

    return embed


# ============================================================
# DEOBFUSCATE COMMAND
# ============================================================

@bot.hybrid_command(
    name="deobfuscate",
    aliases=[
        "deobf",
    ],
    description="Deobfuscate Lua from an attachment, URL, reply, codeblock, or raw code.",
)
async def deobfuscate_command(
    ctx: commands.Context,
    source: Optional[str] = None,
    attachment: Optional[discord.Attachment] = None,
):
    if not await check_bot_access(
        ctx
    ):
        return

    # Prefix commands need the full text after `.deobf` / `.deobfuscate`.
    # Keeping `source` before `attachment` also prevents Discord.py from
    # trying to convert a URL/code argument into an Attachment first.
    resolved_source = source

    if ctx.interaction is None and ctx.message is not None:
        message_content = str(ctx.message.content or "")
        match = re.match(r"^\s*\S+\s*(.*)$", message_content, re.DOTALL)
        if match:
            remainder = match.group(1).strip()
            if remainder:
                resolved_source = remainder

    if is_deobfuscation_blacklisted(
        resolved_source,
        getattr(attachment, "filename", None),
        getattr(attachment, "url", None),
    ):
        await ctx.send(
            embed=deobf_embed(
                "Deobfuscation Blacklisted",
                "This source is excluded from deobfuscation.",
                discord.Color.red(),
            ),
            ephemeral=bool(ctx.interaction),
        )
        return

    try:
        code, filename = await resolve_script_input(
            ctx,
            attachment=attachment,
            source=resolved_source,
        )

        if is_deobfuscation_blacklisted(
            code,
            filename,
        ):
            await ctx.send(
                embed=deobf_embed(
                    "Deobfuscation Blacklisted",
                    "This source is excluded from deobfuscation.",
                    discord.Color.red(),
                ),
                ephemeral=bool(ctx.interaction),
            )
            return

    except Exception as exc:
        await ctx.send(
            embed=deobf_embed(
                "Invalid Input",
                (
                    "```text\n"
                    f"{trim(exc, 1500)}"
                    "\n```"
                ),
                discord.Color.red(),
            ),
            ephemeral=bool(
                ctx.interaction
            ),
        )

        return

    premium = await is_premium_user(ctx)

    view = DeobfuscatorView(
        ctx.author.id,
        filename,
        premium,
    )

    message = await ctx.send(
        embed=view.make_embed(),
        view=view,
    )

    backend = await view.future

    if backend is None:
        return

    if backend not in view.allowed_backends:
        await message.edit(
            embed=deobf_embed(
                "Backend Unavailable",
                "That backend is not available for your account.",
                discord.Color.red(),
            ),
            view=None,
        )
        return

    await message.edit(
        embed=deobf_embed(
            "Processing",
            (
                f"Backend: "
                f"**{BACKEND_NAMES[backend]}**\n\n"
                "Deobfuscating..."
            ),
            discord.Color.orange(),
        ),
        view=None,
    )

    try:
        (
            result,
            detected,
            actual_backend,
            confidence,
        ) = await run_selected_deobfuscator(
            backend,
            code,
        )

        # Never upload/gate backend garbage, comment-only output, or visibly
        # truncated Lua. This runs before Rubis and the Luraph v15 gate.
        result = validate_deobfuscated_output(result)

        result_bytes = result.encode(
            "utf-8",
            errors="replace",
        )

        rubis = await create_rubis_scrap(
            result,
            title="deobfuscated.lua",
        )

        raw_url = (
            rubis.get("raw")
            if rubis
            else None
        )

        view_url = (
            rubis.get("view")
            if rubis
            else None
        )

        # Keep the original interaction/processing message alive.
        # Deleting it breaks hybrid/slash-command followups with Discord 10008
        # (Unknown Message), because the interaction response no longer exists.
        if actual_backend == "luraph15":
            if rubis is None:
                raise RuntimeError(
                    "Rubis upload failed, so the Luraph v15 result link could not be created."
                )

            if has_luraph_gate_bypass_role(ctx.author):
                result_view = v2_card(
                    "✅ Luraph v15 Deobfuscation Complete",
                    "Premium role detected — LootLabs skipped.",
                    accent=discord.Color.green(),
                    blocks=[
                        ("Detected", f"`{detected}`"),
                        (
                            "Backend",
                            f"`{actual_backend}` • confidence `{confidence:.0%}`",
                        ),
                        (
                            "Premium bypass",
                            "Your premium role bypassed the LootLabs gate.",
                        ),
                    ],
                    filename="deobfuscated.lua",
                    raw_url=raw_url,
                    view_url=view_url,
                    footer=f"Requested by {ctx.author} • Oxygen",
                )

                await send_v2(
                    ctx,
                    result_view,
                    content=ctx.author.mention,
                    file=discord.File(
                        io.BytesIO(result_bytes),
                        filename="deobfuscated.lua",
                    ),
                    reply=False,
                )
            else:
                destination_url = view_url or raw_url
                protected_link = await create_luraph_v15_gate(destination_url)

                result_view = v2_card(
                    "✅ Luraph v15 Deobfuscation Complete",
                    "Complete the LootLabs task to unlock your result.",
                    accent=discord.Color.green(),
                    blocks=[
                        ("Detected", f"`{detected}`"),
                        (
                            "Backend",
                            f"`{actual_backend}` • confidence `{confidence:.0%}`",
                        ),
                        (
                            "Protected result",
                            "The direct Rubis links and Discord attachment are hidden behind the protected link.",
                        ),
                    ],
                    protected_url=protected_link,
                    footer=f"Requested by {ctx.author} • Oxygen",
                )

                await send_v2(
                    ctx,
                    result_view,
                    content=ctx.author.mention,
                    reply=False,
                )
        else:
            blocks = [
                (
                    "Detected",
                    f"`{detected}`"
                ),
                (
                    "Backend",
                    f"`{actual_backend}` • confidence `{confidence:.0%}`"
                ),
                (
                    "Preview",
                    "```lua\n"
                    + oxygen_preview(
                        result,
                        1300,
                    )
                    + "\n```"
                ),
            ]

            if rubis is None:
                blocks.append(
                    (
                        "Raw",
                        "Rubis raw upload was unavailable; "
                        "the Discord file is still attached below."
                    )
                )

            result_view = v2_card(
                "✅ Deobfuscation Complete",
                "Output is attached inside this result card.",
                accent=discord.Color.green(),
                blocks=blocks,
                filename="deobfuscated.lua",
                raw_url=raw_url,
                view_url=view_url,
                footer=f"Requested by {ctx.author} • Oxygen",
            )

            await send_v2(
                ctx,
                result_view,
                file=discord.File(
                    io.BytesIO(result_bytes),
                    filename="deobfuscated.lua",
                ),
                reply=False,
            )

        try:
            await message.edit(
                embed=deobf_embed(
                    "Complete",
                    f"Backend: **{BACKEND_NAMES[backend]}**\n\nResult sent below.",
                    discord.Color.green(),
                ),
                view=None,
            )
        except discord.HTTPException:
            pass

    except Exception as exc:
        await message.edit(
            embed=manual_failure_embed(
                BACKEND_NAMES.get(
                    backend,
                    backend,
                ),
                exc,
            )
        )


# ============================================================
# SUPPORTED
# ============================================================

@bot.hybrid_command(
    name="supported",
    description="Show supported deobfuscators.",
)
async def supported_command(
    ctx: commands.Context,
):
    if not await check_bot_access(ctx):
        return

    view = v2_card(
        "🧩 Supported Deobfuscators",
        "Backends currently wired into Oxygen.",
        blocks=[
            (
                "IronBrew / VM",
                "• IronBrew 1\n"
                "• IronBrew 2 / AztupBrew\n"
                "• IronBrew 3\n"
                "• Luraph v14.7 — Free / direct result\n"
                "• Luraph v14.8 — Free / direct result\n"
                "• Luraph v14.9 — Free / direct result\n"
                "• Luraph v15 — LootLabs protected\n"
                "• Prometheus\n"
                "• Clyde\n"
                "• Goofyscator"
            ),
            (
                "Other",
                "• LuaObfuscator\n"
                "• wYnFuscate v4 — currently being worked on"
            ),
        ],
        footer=f"Requested by {ctx.author} • Oxygen",
    )

    await send_v2(
        ctx,
        view,
        ephemeral=bool(ctx.interaction),
    )


# ============================================================
# OXYGEN
# ============================================================

from pathlib import Path

RADIUM_DIR = Path(
    r"C:\Users\Bitra\Downloads\oxyenv_prism_compat\oxyenv"
)

RADIUM_HOST = r"C:\Users\Bitra\Downloads\oxyenv_prism_compat\oxyenv\build\radium-host.exe"
RADIUM_CORE = r"C:\Users\Bitra\Downloads\oxyenv_prism_compat\oxyenv\radium.lua"


def build_l3_args(
    profile,
    input_path,
    output_path,
    *,
    deep=False,
):
    args = [
        str(RADIUM_HOST),
        str(RADIUM_CORE),
        str(input_path),
        str(output_path),
        "--username",
        str(profile["user_name"]),
        "--display-name",
        str(profile["display_name"]),
        "--user-id",
        str(profile["user_id"]),
        "--place-id",
        str(profile["place_id"]),
        "--game-id",
        str(profile["game_id"]),
        "--place-version",
        str(profile["place_version"]),
        "--executor-name",
        str(profile["executor_name"]),
    ]

    if deep:
        args.append("--trace-properties")

    return args


def build_l2_env(
    profile,
    discord_user_id,
):
    env = os.environ.copy()

    env.update(
        {
            "ROBLOX_PLACE_ID":
                str(profile["place_id"]),

            "ROBLOX_GAME_ID":
                str(profile["game_id"]),

            "ROBLOX_USERNAME":
                str(profile["user_name"]),

            "ROBLOX_DISPLAY_NAME":
                str(profile["display_name"]),

            "ROBLOX_USER_ID":
                str(profile["user_id"]),

            "ROBLOX_LOCALE":
                str(profile["locale"]),

            "ROBLOX_MEMBERSHIP_TYPE":
                str(profile["membership_type"]),

            "ROBLOX_EXECUTOR_NAME":
                str(profile["executor_name"]),

            "DISCORD_USER_ID":
                str(discord_user_id),
        }
    )

    return env


def build_roblox_http_headers(profile):
    locale = str(profile.get("locale") or "en-us")
    executor = str(profile.get("executor_name") or "Madium")

    place_id = str(profile.get("place_id", 1818))
    game_id = str(profile.get("game_id", 6767))
    place_version = str(profile.get("place_version", 1))
    user_id = str(profile.get("user_id", 1))
    user_name = str(profile.get("user_name", "Player"))
    membership = str(profile.get("membership_type", "None"))

    return {
        "User-Agent": "Roblox/WinInet",
        "Accept": "*/*",
        "Accept-Language": f"{locale},en;q=0.9",
        "Cache-Control": "no-cache",
        "Pragma": "no-cache",
        "Connection": "keep-alive",
        "Origin": "https://www.roblox.com",
        "Referer": "https://www.roblox.com/",

        "Roblox-Place-Id": place_id,
        "Roblox-Game-Id": game_id,
        "Roblox-Place-Version": place_version,
        "Roblox-User-Id": user_id,
        "Roblox-User-Name": user_name,
        "Roblox-Client-Locale": locale,
        "Roblox-Membership-Type": membership,
        "Roblox-Executor-Name": executor,

        "X-Roblox-Place-Id": place_id,
        "X-Roblox-Game-Id": game_id,
        "X-Roblox-Place-Version": place_version,
        "X-Roblox-User-Id": user_id,
        "X-Roblox-User-Name": user_name,
        "X-Roblox-Client-Locale": locale,
        "X-Roblox-Membership-Type": membership,
        "X-Roblox-Executor-Name": executor,

        "X-Executor-Name": executor,
        "X-Executor-Version": "1.0.0",
    }


def extract_first_url(value):
    value = strip_codeblock(str(value or "")).strip()
    match = re.search(r"https?://[^\s<>`]+", value, re.IGNORECASE)

    if not match:
        return None

    return match.group(0).rstrip(".,);]}>\"'")


async def resolve_fetch_url(ctx, source=None):
    url = extract_first_url(source)

    if url:
        return url

    if ctx.message and ctx.message.attachments:
        return ctx.message.attachments[0].url

    replied = await get_replied_message(ctx)

    if replied:
        if replied.attachments:
            return replied.attachments[0].url

        url = extract_first_url(replied.content)
        if url:
            return url

    raise ValueError(
        "Give me a URL, attach a file, or reply to a message containing one."
    )


IPV4_RE = re.compile(
    r"(?<![\d.])"
    r"(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|1?\d?\d)"
    r"(?![\d.])"
)


def redact_fetched_ips(value):
    value = str(value or "")

    return IPV4_RE.sub(
        "-- erm rel ip : 127.0.0.1",
        value,
    )


def oxygen_preview(value, limit=1350):
    value = str(value or "").replace("```", "~~~").strip()

    if not value:
        return "-- no logged output --"

    if len(value) > limit:
        return value[:limit] + "\n-- preview truncated --"

    return value


RUBIS_SCRAP_ENDPOINT = "https://api.rubis.app/v2/scrap"
RUBIS_SOFT_LIMIT = 2_900_000


def _require_components_v2():
    required = (
        "LayoutView",
        "Container",
        "TextDisplay",
        "Separator",
        "File",
        "ActionRow",
    )

    missing = [
        name
        for name in required
        if not hasattr(discord.ui, name)
    ]

    if missing:
        raise RuntimeError(
            "Discord Components v2 requires discord.py >= 2.6. "
            "Missing: " + ", ".join(missing)
        )


async def create_rubis_scrap(
    content,
    *,
    title="Oxygen Output",
):
    content = str(content or "")

    encoded = content.encode(
        "utf-8",
        errors="replace",
    )

    if not encoded:
        return None

    if len(encoded) > RUBIS_SOFT_LIMIT:
        return None

    access_key = uuid.uuid4().hex + uuid.uuid4().hex[:8]

    params = {
        "public": "false",
        "accessKey": access_key,
        "title": str(title or "Oxygen Output")[:64],
    }

    headers = {
        "Accept": "application/json",
        "Content-Type": "text/plain; charset=utf-8",
        "User-Agent": "Oxygen/1.0",
    }

    timeout = aiohttp.ClientTimeout(total=20)

    try:
        async with aiohttp.ClientSession(
            timeout=timeout,
        ) as session:
            async with session.post(
                RUBIS_SCRAP_ENDPOINT,
                params=params,
                data=encoded,
                headers=headers,
            ) as response:
                raw_text = await response.text()

                if response.status != 200:
                    return None

                try:
                    data = json.loads(raw_text)
                except Exception:
                    return None

    except Exception:
        return None

    if not isinstance(data, dict) or not data.get("success"):
        return None

    raw_url = (
        data.get("raw_with_key")
        or data.get("raw")
    )

    view_url = (
        data.get("view_with_key")
        or data.get("view")
    )

    if not raw_url:
        return None

    return {
        "raw": str(raw_url),
        "view": str(view_url) if view_url else None,
        "scrap_id": data.get("scrapID"),
        "title": data.get("title"),
    }


async def create_luraph_v15_gate(destination_url):
    destination_url = str(destination_url or "").strip()

    if not destination_url:
        raise RuntimeError("Rubis did not return a destination URL for the Luraph v15 result.")

    if not BYPASS_API_KEY:
        raise RuntimeError("BYPASS_API_KEY is not configured.")

    if not LOOTLABS_API_KEY:
        raise RuntimeError("LOOTLABS_API_KEY is not configured.")

    payload = {
        "url": destination_url,
        "pikey": LOOTLABS_API_KEY,
        "provider": "lootlabs",
        "Identificator": "oxygen-luraph-v15",
        "jsonDetections": {
            "Referer": True,
            "MaxTasks": "3",
            "tier_id": 3,
            "Presets": {
                "BYPASS.VIP": True,
                "BYPASS.CITY": True,
                "TRW-API": True,
            },
            "MinTime": "1",
            "DetectUserscripts": True,
            "UnicodeDetect": True,
            "SpoofCompletion": True,
            "VMConfig": {
                "enabled": True,
                "VMode": "medium",
            },
        },
    }

    timeout = aiohttp.ClientTimeout(total=25)

    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.post(
            BYPASS_PUBLISHER_ENDPOINT,
            json=payload,
            headers={
                "c-api-key": BYPASS_API_KEY,
                "Content-Type": "application/json",
            },
        ) as response:
            raw_text = await response.text()

            try:
                data = json.loads(raw_text)
            except Exception:
                data = None

            if response.status < 200 or response.status >= 300:
                reason = (
                    data.get("THReason")
                    if isinstance(data, dict)
                    else raw_text
                )
                raise RuntimeError(
                    f"Anti-bypass API returned HTTP {response.status}: {trim(reason, 500)}"
                )

    if not isinstance(data, dict) or not data.get("success"):
        reason = data.get("THReason") if isinstance(data, dict) else "invalid response"
        raise RuntimeError(f"Anti-bypass API rejected the link: {reason}")

    protected_link = str(data.get("link") or "").strip()

    if not protected_link:
        raise RuntimeError("Anti-bypass API returned no protected link.")

    return protected_link


def v2_card(
    title,
    body=None,
    *,
    accent=None,
    blocks=None,
    filename=None,
    raw_url=None,
    view_url=None,
    source_url=None,
    protected_url=None,
    footer=None,
):
    _require_components_v2()

    view = discord.ui.LayoutView(timeout=None)

    container = discord.ui.Container(
        accent_colour=(
            accent
            if accent is not None
            else discord.Color.from_rgb(88, 101, 242)
        )
    )

    header = f"## {title}"

    if body:
        header += f"\n{body}"

    container.add_item(
        discord.ui.TextDisplay(header)
    )

    for block_title, block_text in (blocks or []):
        container.add_item(
            discord.ui.Separator()
        )

        container.add_item(
            discord.ui.TextDisplay(
                f"### {block_title}\n{block_text}"
            )
        )

    if filename:
        container.add_item(
            discord.ui.Separator()
        )

        container.add_item(
            discord.ui.TextDisplay(
                "### Output file"
            )
        )

        container.add_item(
            discord.ui.File(
                f"attachment://{filename}"
            )
        )

    links = []

    if raw_url:
        links.append(
            discord.ui.Button(
                label="Open raw",
                emoji="🔗",
                style=discord.ButtonStyle.link,
                url=raw_url,
            )
        )

    if view_url:
        links.append(
            discord.ui.Button(
                label="View on Rubis",
                emoji="📄",
                style=discord.ButtonStyle.link,
                url=view_url,
            )
        )

    if source_url:
        links.append(
            discord.ui.Button(
                label="Source",
                emoji="🌐",
                style=discord.ButtonStyle.link,
                url=source_url,
            )
        )

    if protected_url:
        links.append(
            discord.ui.Button(
                label="Unlock result",
                emoji=LURAPH_EMOJI,
                style=discord.ButtonStyle.link,
                url=protected_url,
            )
        )

    if links:
        row = discord.ui.ActionRow()

        for button in links[:5]:
            row.add_item(button)

        container.add_item(
            discord.ui.Separator()
        )

        container.add_item(row)

    if footer:
        container.add_item(
            discord.ui.Separator()
        )

        container.add_item(
            discord.ui.TextDisplay(
                f"-# {footer}"
            )
        )

    view.add_item(container)

    return view


async def send_v2(
    ctx,
    view,
    *,
    file=None,
    files=None,
    content=None,
    reply=False,
    ephemeral=False,
):
    kwargs = {
        "view": view,
    }

    if content is not None:
        # Discord Components V2 (LayoutView/TextDisplay/Container) forbids the
        # normal message `content` field. Put the text inside the component
        # payload instead. This also keeps mentions visible without triggering
        # HTTP 50035: MessageFlags.IS_COMPONENTS_V2 + content.
        if isinstance(view, discord.ui.LayoutView):
            view.add_item(
                discord.ui.TextDisplay(
                    str(content)
                )
            )
        else:
            kwargs["content"] = content

    if file is not None:
        kwargs["file"] = file

    if files is not None:
        kwargs["files"] = files

    if reply:
        kwargs["mention_author"] = False
        return await ctx.reply(**kwargs)

    kwargs["ephemeral"] = bool(ephemeral)
    return await ctx.send(**kwargs)


async def get_attachment(
    ctx,
    supplied=None,
):
    if supplied is not None:
        return supplied

    if (
        ctx.message
        and ctx.message.attachments
    ):
        return ctx.message.attachments[0]

    replied = await get_replied_message(
        ctx
    )

    if (
        replied
        and replied.attachments
    ):
        return replied.attachments[0]

    return None


async def run_radium_job(
    ctx,
    attachment,
    mode,
):
    attachment = await get_attachment(
        ctx,
        attachment,
    )

    if attachment is None:
        await ctx.send(
            embed=radium_embed(
                "No Input",
                (
                    "Attach or reply to a "
                    "`.lua`, `.luau`, or `.txt` file."
                ),
                discord.Color.red(),
            ),
            ephemeral=bool(
                ctx.interaction
            ),
        )

        return

    if (
        Path(
            attachment.filename
        ).suffix.lower()
        not in ALLOWED_EXTENSIONS
    ):
        await ctx.send(
            embed=radium_embed(
                "Unsupported File",
                (
                    "Only `.lua`, `.luau`, "
                    "and `.txt` are supported."
                ),
                discord.Color.red(),
            ),
            ephemeral=bool(
                ctx.interaction
            ),
        )

        return

    profile = get_profile(
        ctx.author.id
    )

    job_id = (
        uuid.uuid4()
        .hex[:10]
        .upper()
    )

    engine = (
        "L3"
    )

    status = await ctx.send(
        embed=radium_embed(
            f"Oxygen • {engine}",
            (
                f"Running job "
                f"`RAD-{job_id}`..."
            ),
            discord.Color.orange(),
        )
    )

    try:
        raw = await attachment.read()

        with tempfile.TemporaryDirectory(
            prefix="radium_"
        ) as temp_dir:

            temp = Path(
                temp_dir
            )

            input_path = (
                temp
                / "input.lua"
            )

            output_path = (
                temp
                / "output.lua"
            )

            input_path.write_bytes(
                raw
            )

            if mode == "l3":
                args = build_l3_args(
                    profile,
                    input_path,
                    output_path,
                )

                returncode, stdout, stderr = await run_process(
                    args,
                    cwd=BASE_DIR,
                )

            elif mode == "l2":
                args = [
                    str(LUNE_PATH),
                    "run",
                    str(L2_SCRIPT),
                    str(input_path),
                    str(output_path),
                ]

                returncode, stdout, stderr = await run_process(
                    args,
                    cwd=BASE_DIR,
                    env=build_l2_env(
                        profile,
                        ctx.author.id,
                    ),
                )

            else:
                raise RuntimeError(
                    f"Unknown mode: {mode}"
                )

            if returncode != 0:
                raise RuntimeError(
                    stderr
                    or stdout
                    or (
                        f"Process exited with "
                        f"{returncode}"
                    )
                )

            if not output_path.exists():
                raise RuntimeError(
                    (
                        "Radium finished without "
                        "creating output.lua."
                    )
                )

            result = output_path.read_bytes()

        await asyncio.sleep(
            2
        )

        await status.edit(
            embed=radium_embed(
                f"Radium Complete • {engine}",
                (
                    f"Job `RAD-{job_id}` completed."
                ),
                discord.Color.green(),
            )
        )

        await ctx.reply(
            file=discord.File(
                io.BytesIO(
                    result
                ),
                filename=(
                    f"radium_{engine.lower()}.lua"
                ),
            ),
            mention_author=False,
        )

    except Exception as exc:
        await status.edit(
            embed=radium_embed(
                f"Radium Failed • {engine}",
                (
                    "```text\n"
                    f"{trim(exc, 1700)}"
                    "\n```"
                ),
                discord.Color.red(),
            )
        )


# ============================================================
# L / L2
# ============================================================

@bot.hybrid_command(
    name="l",
    aliases=["log"],
    description="Run Oxygen L3 from code, URL, attachment, or reply.",
)
async def l_command(
    ctx: commands.Context,
    *,
    source: str = None,
):
    if not await is_premium_user(ctx):
        view = v2_card(
            "🔒 Premium Required",
            "The `.l` Oxygen environment logger is available to premium users only.",
            accent=discord.Color.gold(),
            footer="Oxygen",
        )

        await send_v2(
            ctx,
            view,
            ephemeral=bool(ctx.interaction),
        )
        return

    deep = False

    if source:
        stripped = source.strip()

        if stripped == "--deep":
            deep = True
            source = None
        elif stripped.startswith("--deep "):
            deep = True
            source = stripped[len("--deep "):].lstrip()

    if ctx.interaction:
        await ctx.defer()
    else:
        await add_reaction(ctx.message, "⏳")

    started = asyncio.get_running_loop().time()

    try:
        code, filename = await resolve_script_input(
            ctx,
            attachment=None,
            source=source,
        )

        source_bytes = code.encode(
            "utf-8",
            errors="replace",
        )

        if len(source_bytes) > 2 * 1024 * 1024:
            raise ValueError(
                "Input is too large. Max size is 2 MB."
            )

        profile = get_profile(ctx.author.id)

        with tempfile.TemporaryDirectory(
            prefix="oxygen_"
        ) as tmp_dir:
            tmp = Path(tmp_dir)
            input_name = clean_filename(
                filename or "input.lua"
            )
            input_path = tmp / input_name
            output_path = tmp / "output.lua"

            input_path.write_bytes(source_bytes)

            args = build_l3_args(
                profile,
                input_path,
                output_path,
                deep=deep,
            )

            returncode, stdout_text, stderr_text = await run_process(
                args,
                cwd=RADIUM_DIR,
                timeout=PROCESS_TIMEOUT,
            )

            result_bytes = (
                output_path.read_bytes()
                if output_path.exists()
                else b""
            )

        elapsed = (
            asyncio.get_running_loop().time()
            - started
        )

        stdout_text = str(stdout_text or "").strip()
        stderr_text = str(stderr_text or "").strip()

        result_text = result_bytes.decode(
            "utf-8",
            errors="replace",
        )

        runtime_match = re.search(
            r"^-- runtime:\s*(.+)$",
            result_text,
            re.MULTILINE,
        )

        runtime_error = (
            runtime_match.group(1).strip()
            if runtime_match
            else None
        )

        process_error = "\n".join(
            value
            for value in (
                stderr_text,
                stdout_text,
            )
            if value
        ).strip()

        failed = (
            returncode != 0
            or runtime_error is not None
        )

        if not result_bytes:
            detail = (
                runtime_error
                or process_error
                or (
                    f"Oxygen exited with code {returncode} "
                    "without creating output.lua."
                )
            )

            view = v2_card(
                "❌ Oxygen failed",
                "Nothing was logged before the runtime stopped.",
                accent=discord.Color.red(),
                blocks=[
                    (
                        "Error",
                        f"```text\n{trim(detail, 1800)}\n```"
                    ),
                    (
                        "Profile",
                        f"Executor `{profile['executor_name']}` • "
                        f"place `{profile['place_id']}` • "
                        f"user `{profile['user_name']}`"
                    ),
                ],
                footer=f"Requested by {ctx.author} • Oxygen",
            )

            await send_v2(
                ctx,
                view,
                reply=True,
            )
            return

        output_name = (
            f"Oxygen_"
            f"{getattr(ctx.message, 'id', None) or uuid.uuid4().hex[:16]}"
            ".lua"
        )

        rubis = await create_rubis_scrap(
            result_text,
            title=output_name,
        )

        raw_url = rubis.get("raw") if rubis else None
        view_url = rubis.get("view") if rubis else None

        if failed:
            title = "⚠️ Logged with a runtime error"
            accent = discord.Color.orange()

            error_detail = (
                runtime_error
                or process_error
                or f"Process exited with {returncode}."
            )

            body = (
                "Everything Oxygen captured before the error "
                "is still included below."
            )

            blocks = [
                (
                    "Error",
                    f"```text\n{trim(error_detail, 1000)}\n```"
                )
            ]
        else:
            title = "✅ Successfully logged"
            accent = discord.Color.green()
            body = (
                "Oxygen finished the run and captured "
                "the script activity."
            )
            blocks = []

        if deep:
            body += "\n`--deep` property tracing was enabled."

        blocks.extend(
            [
                (
                    "Preview",
                    "```lua\n"
                    + oxygen_preview(
                        result_text,
                        1400,
                    )
                    + "\n```"
                ),
                (
                    "Environment",
                    f"Executor `{profile['executor_name']}` • "
                    f"Place `{profile['place_id']}` • "
                    f"Game `{profile['game_id']}`\n"
                    f"Player `{profile['user_name']}` • "
                    f"User ID `{profile['user_id']}`"
                ),
                (
                    "Run",
                    f"`{elapsed:.2f}s` • "
                    f"`{len(result_bytes):,}` bytes"
                ),
            ]
        )

        if rubis is None:
            blocks.append(
                (
                    "Raw",
                    "Rubis raw upload was unavailable; "
                    "the Discord file is still attached below."
                )
            )

        view = v2_card(
            title,
            body,
            accent=accent,
            blocks=blocks,
            filename=output_name,
            raw_url=raw_url,
            view_url=view_url,
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            file=discord.File(
                io.BytesIO(result_bytes),
                filename=output_name,
            ),
            reply=True,
        )

    except FileNotFoundError:
        view = v2_card(
            "❌ Oxygen host missing",
            f"`{RADIUM_HOST}`",
            accent=discord.Color.red(),
            footer="Oxygen",
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    except Exception as exc:
        view = v2_card(
            "❌ Command Error",
            "The run could not be started.",
            accent=discord.Color.red(),
            blocks=[
                (
                    "Error",
                    "```text\n"
                    + trim(
                        type(exc).__name__
                        + ": "
                        + str(exc),
                        1700,
                    )
                    + "\n```"
                )
            ],
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    finally:
        if not ctx.interaction:
            await remove_reaction(
                ctx.message,
                "⏳",
            )




# ============================================================
# EXECUTOR-STYLE HTTP
# ============================================================

async def executor_request(
    session,
    *,
    url,
    method="GET",
    headers=None,
    body=None,
    timeout=None,
):
    """
    aiohttp wrapper shaped similarly to common Roblox executor request APIs.

    Returns:
        {
            "Success": bool,
            "StatusCode": int,
            "StatusMessage": str,
            "Headers": dict,
            "Body": str,
            "Url": str,
        }
    """
    request_headers = dict(headers or {})

    request_timeout = (
        aiohttp.ClientTimeout(total=timeout)
        if timeout
        else None
    )

    async with session.request(
        method=str(method or "GET").upper(),
        url=str(url),
        headers=request_headers or None,
        data=body,
        allow_redirects=True,
        timeout=request_timeout,
    ) as response:
        raw = await response.read()

        if len(raw) > MAX_FILE_SIZE:
            raise ValueError(
                "HTTP response is larger than "
                f"{MAX_FILE_SIZE // (1024 * 1024)} MB."
            )

        return {
            "Success": 200 <= response.status < 400,
            "StatusCode": response.status,
            "StatusMessage": response.reason or "",
            "Headers": dict(response.headers),
            "Body": raw.decode(
                "utf-8",
                errors="replace",
            ),
            "Url": str(response.url),
        }



def nexomia_headers(
    profile,
    fingerprint=None,
):
    """
    Build the observable Nexomia-style HTTP headers seen from executor requests.

    This is intended for the user's own loader/service testing.
    Host and Content-Length are intentionally omitted because aiohttp calculates
    them automatically.
    """
    place_id = str(
        profile.get(
            "place_id",
            "",
        )
        or ""
    )

    game_id = str(
        profile.get(
            "game_id",
            "",
        )
        or ""
    )

    fingerprint = str(
        fingerprint
        or profile.get(
            "nexomia_fingerprint",
            "",
        )
        or ""
    ).strip()

    headers = {
        "Accept": "*/*",
        "Accept-Encoding": "deflate, gzip",
        "User-Agent": "Nexomia",
        "Exploitidentifier": "Nexomia.win",
        "Roblox-Game-Id": game_id,
        "Roblox-Place-Id": place_id,
        "Roblox-Session-Id": json.dumps(
            {
                "GameId": game_id,
                "PlaceId": place_id,
            },
            separators=(",", ":"),
        ),
    }

    if fingerprint:
        headers["Exploit-Guid"] = fingerprint
        headers["Nexomia-Fingerprint"] = fingerprint

    return headers


async def nexomia_request(
    session,
    *,
    url,
    profile,
    method="GET",
    body=None,
    headers=None,
    fingerprint=None,
    timeout=None,
):
    merged_headers = nexomia_headers(
        profile,
        fingerprint=fingerprint,
    )

    if headers:
        merged_headers.update(
            headers
        )

    return await executor_request(
        session,
        url=url,
        method=method,
        headers=merged_headers,
        body=body,
        timeout=timeout,
    )



@bot.command(
    name="nexomiafp",
)
async def nexomia_fingerprint_command(
    ctx: commands.Context,
    *,
    fingerprint: str = None,
):
    """
    Set or inspect the Nexomia fingerprint used by .fetch.

    .nexomiafp
    .nexomiafp 4732E7D79E900DCB4A19BCEE604C34
    .nexomiafp clear
    """
    if not await check_bot_access(ctx):
        return

    profile = get_profile(
        ctx.author.id
    )

    if fingerprint is None:
        current = (
            profile.get(
                "nexomia_fingerprint",
            )
            or "not set"
        )

        await ctx.reply(
            f"Nexomia fingerprint: `{current}`"
        )
        return

    fingerprint = fingerprint.strip()

    if fingerprint.lower() in {
        "clear",
        "none",
        "reset",
    }:
        update_profile(
            ctx.author.id,
            {
                "nexomia_fingerprint": "",
            },
        )

        await ctx.reply(
            "Nexomia fingerprint cleared."
        )
        return

    if not re.fullmatch(
        r"[A-Fa-f0-9]{16,128}",
        fingerprint,
    ):
        await ctx.reply(
            "Fingerprint must be a hexadecimal string."
        )
        return

    update_profile(
        ctx.author.id,
        {
            "nexomia_fingerprint": fingerprint,
        },
    )

    await ctx.reply(
        "Nexomia fingerprint saved for your `.fetch` requests."
    )


# ============================================================
# FETCH
# ============================================================

FETCH_MAX_DEPTH = 8
JNKIE_DELIVERY_BASE = "https://api.jnkie.com/api/v1/luascripts/delivery/"

LOADSTRING_HTTPGET_RE = re.compile(
    r"""loadstring\s*\(\s*(?:game\s*:\s*)?HttpGet\s*\(\s*["']([^"']+)["']\s*(?:,\s*[^)]*)?\)\s*\)\s*\(\s*\)""",
    re.IGNORECASE | re.DOTALL,
)

HTTPGET_URL_RE = re.compile(
    r"""(?:game\s*:\s*)?HttpGet\s*\(\s*["']([^"']+)["']""",
    re.IGNORECASE | re.DOTALL,
)

JNKIE_SCRIPT_IDS_RE = re.compile(
    r"""local\s+S\s*,\s*P\s*,\s*G\s*=\s*\{(?P<s>.*?)\}\s*,\s*\{(?P<p>.*?)\}\s*,\s*\{(?P<g>.*?)\}""",
    re.IGNORECASE | re.DOTALL,
)

LUA_STRING_RE = re.compile(
    r"""["']([0-9a-fA-F]{32,128})["']"""
)

LUA_NUM_MAP_RE = re.compile(
    r"""\[\s*(\d+)\s*\]\s*=\s*(\d+)"""
)


def extract_loader_url(value):
    text = strip_codeblock(str(value or "")).strip()

    direct = _direct_url_from_text(text)
    if direct:
        return direct

    match = LOADSTRING_HTTPGET_RE.search(text)
    if match:
        return match.group(1).strip()

    match = HTTPGET_URL_RE.search(text)
    if match:
        return match.group(1).strip()

    return None


def split_fetch_input(value):
    """
    Accept:
      .fetch <url>
      .fetch <url> KEY
      .fetch loadstring(game:HttpGet("..."))()
      .fetch loadstring(game:HttpGet("..."))() KEY

    Returns (loader_text_or_url, optional_script_key).
    """
    text = str(value or "").strip()

    if not text:
        return None, None

    # Whole loadstring(...)() first, leaving anything after it as the key.
    m = re.match(
        r"""(?is)^\s*(loadstring\s*\(\s*(?:game\s*:\s*)?HttpGet\s*\(\s*["'][^"']+["']\s*(?:,\s*[^)]*)?\)\s*\)\s*\(\s*\))\s*(.*?)\s*$""",
        text,
    )

    if m:
        loader = m.group(1).strip()
        key = m.group(2).strip() or None
        return loader, key

    # Direct URL followed by an optional key.
    m = re.match(
        r"""(?is)^\s*(https?://[^\s<>`]+)(?:\s+(.+?))?\s*$""",
        text,
    )

    if m:
        loader = m.group(1).rstrip(".,);]}>\"'")
        key = (m.group(2) or "").strip() or None
        return loader, key

    # If it isn't recognizable as a loader, let reply-mode treat this as a key.
    return None, text


def looks_like_loader_stub(source):
    source = str(source or "").strip()

    if not source or len(source) > 100_000:
        return False

    return bool(
        LOADSTRING_HTTPGET_RE.fullmatch(source)
        or re.fullmatch(
            r"""\s*(?:return\s+)?loadstring\s*\(\s*(?:game\s*:\s*)?HttpGet\s*\(\s*["'][^"']+["']\s*(?:,\s*[^)]*)?\)\s*\)\s*\(\s*\)\s*;?\s*""",
            source,
            re.IGNORECASE | re.DOTALL,
        )
    )


def parse_jnkie_delivery(source, profile):
    """
    Parse Jnkie's generated:
        local S,P,G={script ids},{[PlaceId]=index},{[GameId]=index}
        local i=P[game.PlaceId] or G[game.GameId]

    and resolve the script ID using the user's configured profile.
    """
    match = JNKIE_SCRIPT_IDS_RE.search(source)

    if not match:
        return None

    script_ids = LUA_STRING_RE.findall(match.group("s"))
    place_map = {
        int(k): int(v)
        for k, v in LUA_NUM_MAP_RE.findall(match.group("p"))
    }
    game_map = {
        int(k): int(v)
        for k, v in LUA_NUM_MAP_RE.findall(match.group("g"))
    }

    place_id = int(profile.get("place_id", 0) or 0)
    game_id = int(profile.get("game_id", 0) or 0)

    index = place_map.get(place_id)

    if index is None:
        index = game_map.get(game_id)

    if index is None:
        known_places = ", ".join(str(x) for x in sorted(place_map)) or "none"
        known_games = ", ".join(str(x) for x in sorted(game_map)) or "none"

        raise ValueError(
            "This Jnkie loader does not contain your configured game.\n"
            f"Configured PlaceId={place_id}, GameId={game_id}\n"
            f"Loader PlaceIds: {known_places}\n"
            f"Loader GameIds: {known_games}\n"
            "Change the profile with your existing config command, then retry."
        )

    if index < 1 or index > len(script_ids):
        raise RuntimeError(
            f"Jnkie loader selected invalid script index {index}."
        )

    return {
        "script_id": script_ids[index - 1],
        "index": index,
        "place_id": place_id,
        "game_id": game_id,
    }


async def resolve_fetch_source(ctx, source=None):
    """
    Resolve both loader and optional SCRIPT_KEY.

    Prefix examples:
      .fetch <loader>
      .fetch <loader> SCRIPT_KEY
      reply to loader: .fetch
      reply to loader: .fetch SCRIPT_KEY
    """
    explicit_loader, explicit_key = split_fetch_input(source)

    if explicit_loader:
        url = extract_loader_url(explicit_loader)

        if not url:
            raise ValueError("Could not extract an HttpGet URL.")

        return url, explicit_key

    replied = await get_replied_message(ctx)

    if replied:
        reply_text = replied.content or ""

        if replied.attachments:
            attachment = replied.attachments[0]

            if attachment.size > MAX_FILE_SIZE:
                raise ValueError("Replied file is too large.")

            data = await attachment.read()
            reply_text = data.decode(
                "utf-8",
                errors="replace",
            )

        reply_loader, reply_key = split_fetch_input(reply_text)

        if reply_loader:
            url = extract_loader_url(reply_loader)

            if not url:
                raise ValueError(
                    "Could not extract an HttpGet URL from the replied loader."
                )

            # `.fetch SOME_KEY` while replying to a loader means SOME_KEY
            # is the key for that replied loader.
            supplied_key = explicit_key or reply_key
            return url, supplied_key

    raise ValueError(
        "Give a URL/Jnkie loadstring, or reply to one. "
        "An optional SCRIPT_KEY may follow the loader."
    )


async def _read_limited_response(response):
    chunks = []
    total_size = 0

    async for chunk in response.content.iter_chunked(
        64 * 1024
    ):
        if not chunk:
            continue

        total_size += len(chunk)

        if total_size > MAX_FILE_SIZE:
            raise ValueError(
                "Fetched data is larger than "
                f"{MAX_FILE_SIZE // (1024 * 1024)} MB."
            )

        chunks.append(chunk)

    return b"".join(chunks)


async def _http_get_text(session, url, headers=None):
    result = await executor_request(
        session,
        url=url,
        method="GET",
        headers=headers,
    )

    body = result["Body"].encode(
        "utf-8",
        errors="replace",
    )

    return (
        result["StatusCode"],
        result["Url"],
        result["Body"],
        body,
    )


async def _http_post_text(session, url, body_text, headers=None):
    request_headers = {
        "Content-Type": "text/plain",
        "Accept": "*/*",
    }

    if headers:
        request_headers.update(headers)

    result = await executor_request(
        session,
        url=url,
        method="POST",
        headers=request_headers,
        body=body_text.encode(
            "utf-8",
            errors="replace",
        ),
    )

    body = result["Body"].encode(
        "utf-8",
        errors="replace",
    )

    return (
        result["StatusCode"],
        result["Url"],
        result["Body"],
        body,
    )


async def fetch_jnkie_payload(
    ctx,
    session,
    loader_source,
    supplied_key=None,
):
    profile = get_profile(
        ctx.author.id
    )

    delivery = parse_jnkie_delivery(
        loader_source,
        profile,
    )

    if not delivery:
        return None

    delivery_url = (
        JNKIE_DELIVERY_BASE
        + delivery["script_id"]
        + "?v=2&errors=text"
    )

    body_key = (
        supplied_key
        if supplied_key
        else "KEYLESS"
    )

    # Match the observable Nexomia request shape used by the user's own loader.
    result = await nexomia_request(
        session,
        url=delivery_url,
        profile=profile,
        method="POST",
        body=body_key.encode(
            "utf-8",
            errors="replace",
        ),
        headers={
            "Content-Type": "text/plain",
            "Accept": "*/*",
        },
        fingerprint=profile.get(
            "nexomia_fingerprint",
        ),
        timeout=35,
    )

    status = result["StatusCode"]
    response_text = result["Body"]
    final_delivery_url = result["Url"]

    if (
        status == 200
        and response_text.strip().startswith(
            "https://cdn.jnkie.com/"
        )
    ):
        cdn_url = response_text.strip()

        cdn_result = await nexomia_request(
            session,
            url=cdn_url,
            profile=profile,
            method="GET",
            headers={
                "Accept": "*/*",
            },
            fingerprint=profile.get(
                "nexomia_fingerprint",
            ),
            timeout=35,
        )

        if (
            cdn_result["StatusCode"] != 200
            or not cdn_result["Body"]
        ):
            raise RuntimeError(
                "Jnkie delivery returned a CDN URL, "
                "but fetching that CDN URL failed with "
                f"HTTP {cdn_result['StatusCode']}."
            )

        return {
            "source": cdn_result["Body"],
            "final_url": cdn_result["Url"],
            "delivery_url": final_delivery_url,
            "auth_mode": (
                "supplied-key"
                if supplied_key
                else "keyless"
            ),
            "script_id": delivery["script_id"],
            "size": len(
                cdn_result["Body"].encode(
                    "utf-8",
                    errors="replace",
                )
            ),
        }

    message = (
        response_text.strip()
        or result["StatusMessage"]
        or "No response body."
    )

    if len(message) > 1000:
        message = message[:1000] + "..."

    if status == 403 and "CORS_NOT_ALLOWED" in message:
        raise RuntimeError(
            "Jnkie still rejected the request with CORS_NOT_ALLOWED. "
            "The Nexomia-style HTTP headers were sent, but the service "
            "is still requiring something not reproduced by this bot "
            "(for example a valid per-client fingerprint/runtime session "
            "or server-side network authorization).\\n\\n"
            + message
        )

    if supplied_key:
        raise RuntimeError(
            "Jnkie delivery failed using the supplied SCRIPT_KEY "
            f"(HTTP {status}).\\n{message}"
        )

    raise RuntimeError(
        "Jnkie keyless delivery failed "
        f"(HTTP {status}).\\n{message}"
    )


async def fetch_loader_chain(
    ctx,
    start_url,
    supplied_key=None,
):
    profile = get_profile(ctx.author.id)

    header_profiles = [
        nexomia_headers(
            profile,
            fingerprint=profile.get(
                "nexomia_fingerprint",
            ),
        ),
        {
            **build_roblox_http_headers(profile),
            "Accept": "*/*",
            "User-Agent": "Roblox/WinInet",
        },
        {
            "User-Agent": "Roblox/WinInet",
            "Accept": "*/*",
        },
        {
            "Accept": "*/*",
        },
    ]

    timeout = aiohttp.ClientTimeout(total=35)

    current_url = start_url
    seen = set()
    chain = []
    final_source = None
    final_url = start_url

    async with aiohttp.ClientSession(
        timeout=timeout,
        auto_decompress=True,
    ) as session:

        for depth in range(1, FETCH_MAX_DEPTH + 1):
            if current_url in seen:
                raise RuntimeError(
                    f"Loader loop detected at {current_url}"
                )

            seen.add(current_url)

            body_text = None
            response_status = None
            response_url = current_url
            last_error = None

            for attempt, headers in enumerate(
                header_profiles,
                1,
            ):
                try:
                    status, resolved_url, text_body, raw_body = (
                        await _http_get_text(
                            session,
                            current_url,
                            headers=headers,
                        )
                    )

                    response_status = status
                    response_url = resolved_url

                    if 200 <= status < 400:
                        body_text = text_body
                        break

                    last_error = (
                        f"attempt {attempt}: HTTP {status}: "
                        f"{text_body[:500]}"
                    )

                except Exception as exc:
                    last_error = (
                        f"attempt {attempt}: "
                        f"{type(exc).__name__}: {exc}"
                    )

            if body_text is None:
                raise RuntimeError(
                    "All request profiles failed while fetching "
                    f"{current_url}\n\n"
                    f"Last error: {last_error}"
                )

            final_url = response_url
            final_source = body_text

            chain.append(
                {
                    "depth": depth,
                    "url": current_url,
                    "final_url": final_url,
                    "size": len(
                        body_text.encode(
                            "utf-8",
                            errors="replace",
                        )
                    ),
                    "status": response_status,
                }
            )

            # If this is a Jnkie generated loader, resolve its protected
            # delivery endpoint without executing any Lua.
            delivery = parse_jnkie_delivery(
                body_text,
                profile,
            )

            if delivery:
                result = await fetch_jnkie_payload(
                    ctx,
                    session,
                    body_text,
                    supplied_key=supplied_key,
                )

                chain.append(
                    {
                        "depth": depth + 1,
                        "url": result["delivery_url"],
                        "final_url": result["final_url"],
                        "size": result["size"],
                        "status": 200,
                        "auth_mode": result["auth_mode"],
                    }
                )

                return (
                    result["source"],
                    result["final_url"],
                    chain,
                    result["auth_mode"],
                )

            if not looks_like_loader_stub(body_text):
                break

            next_url = extract_loader_url(body_text)

            if not next_url or next_url == current_url:
                break

            current_url = next_url

    if final_source is None:
        raise RuntimeError(
            "No response body was fetched."
        )

    return final_source, final_url, chain, "none"



def make_safe_fetch_wrapper(fetched_source, suggested_name="jnkie_loader.lua"):
    """
    Build a Roblox-side wrapper around source that the bot already fetched.
    This does not hook loadstring/request or intercept later protected payloads.
    """
    safe_name = re.sub(
        r"[^A-Za-z0-9._-]",
        "_",
        str(suggested_name or "jnkie_loader.lua"),
    )

    # Use a long-bracket delimiter that does not occur in the source.
    eq = ""
    while f"]{eq}]" in fetched_source:
        eq += "="

    open_bracket = f"[{eq}["
    close_bracket = f"]{eq}]"

    return (
        f'local source = {open_bracket}{fetched_source}{close_bracket}\n\n'
        f'local outputName = "{safe_name}"\n'
        'local detectedSetmetatable = source:find("return setmetatable", 1, true) ~= nil\n\n'
        'if writefile then\n'
        '    writefile(outputName, source)\n'
        '    if detectedSetmetatable then\n'
        '        local stem = outputName:gsub("%.lua$", "")\n'
        '        writefile(stem .. "_setmetatable.lua", source)\n'
        '    end\n'
        'end\n\n'
        'print("[fetch] saved:", outputName)\n'
        'print("[fetch] return setmetatable:", detectedSetmetatable)\n\n'
        '-- Optional: execute the public loader source you explicitly fetched.\n'
        '-- local fn, err = loadstring(source)\n'
        '-- if not fn then error(err) end\n'
        '-- return fn()\n'
    )


@bot.command(
    name="fetch",
)
async def fetch_command(
    ctx: commands.Context,
    *,
    source: str = None,
):
    """
    Prefix-only loader fetcher.

    Examples:
      .fetch https://api.jnkie.com/...
      .fetch https://api.jnkie.com/... SCRIPT_KEY
      .fetch loadstring(game:HttpGet("https://api.jnkie.com/..."))()
      .fetch loadstring(game:HttpGet("https://api.jnkie.com/..."))() SCRIPT_KEY

      Reply to a loader:
        .fetch
        .fetch SCRIPT_KEY

    Lua is never executed by this command.
    """

    if not await check_bot_access(ctx):
        return

    await add_reaction(
        ctx.message,
        "🔗",
    )

    try:
        start_url, supplied_key = await resolve_fetch_source(
            ctx,
            source,
        )

        fetched, final_url, chain, auth_mode = (
            await fetch_loader_chain(
                ctx,
                start_url,
                supplied_key=supplied_key,
            )
        )

        fetched = redact_fetched_ips(fetched)

        output_name = "jnkie_loader.lua"
        output_bytes = fetched.encode(
            "utf-8",
            errors="replace",
        )

        wrapper_text = make_safe_fetch_wrapper(
            fetched,
            suggested_name=output_name,
        )
        wrapper_bytes = wrapper_text.encode(
            "utf-8",
            errors="replace",
        )

        rubis = None

        try:
            rubis = await create_rubis_scrap(
                fetched,
                title=output_name,
            )

        except Exception as rubis_error:
            print(
                "[FETCH] Rubis upload failed:",
                repr(rubis_error),
            )

        raw_url = (
            rubis.get("raw")
            if rubis
            else None
        )

        view_url = (
            rubis.get("view")
            if rubis
            else None
        )

        chain_text = "\n".join(
            f"`{item['depth']}` • "
            f"`{item['size']:,}` bytes • "
            f"{item['final_url']}"
            for item in chain
        )

        auth_text = {
            "supplied-key": "SCRIPT_KEY",
            "keyless": "KEYLESS",
            "none": "Not required",
        }.get(
            auth_mode,
            auth_mode,
        )

        blocks = [
            (
                "Preview",
                "```lua\n"
                + oxygen_preview(
                    fetched,
                    1300,
                )
                + "\n```",
            ),
            (
                "Fetch",
                f"`{len(output_bytes):,}` bytes • "
                f"`{len(chain)}` request(s)\n"
                + trim(
                    chain_text,
                    1200,
                ),
            ),
            (
                "Authorization",
                f"`{auth_text}`",
            ),
            (
                "Safety",
                "Downloaded as text only. "
                "No `loadstring` or Lua was executed.",
            ),
        ]

        view = v2_card(
            "✅ Loader fetched",
            "Fetched the final loader source.",
            accent=discord.Color.green(),
            blocks=blocks,
            filename=output_name,
            raw_url=raw_url,
            view_url=view_url,
            source_url=final_url,
            footer=(
                f"Requested by {ctx.author} • Oxygen"
            ),
        )

        files = [
            discord.File(
                io.BytesIO(output_bytes),
                filename=output_name,
            ),
            discord.File(
                io.BytesIO(wrapper_bytes),
                filename="jnkie_fetch_wrapper.lua",
            ),
        ]

        await send_v2(
            ctx,
            view,
            files=files,
            reply=True,
        )

    except Exception as exc:
        view = v2_card(
            "❌ Fetch failed",
            "Could not fetch that loader.",
            accent=discord.Color.red(),
            blocks=[
                (
                    "Error",
                    "```text\n"
                    + trim(
                        type(exc).__name__
                        + ": "
                        + str(exc),
                        1700,
                    )
                    + "\n```",
                )
            ],
            footer=(
                f"Requested by {ctx.author} • Oxygen"
            ),
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    finally:
        await remove_reaction(
            ctx.message,
            "🔗",
        )


# ============================================================
# GET
@bot.hybrid_command(
    name="get",
    description="Fetch a URL without custom request headers.",
)
async def get_command(
    ctx: commands.Context,
    *,
    url: str = None,
):
    if not await check_bot_access(ctx):
        return

    if ctx.interaction:
        await ctx.defer()
    else:
        await add_reaction(ctx.message, "🔗")

    started = asyncio.get_running_loop().time()

    try:
        target = await resolve_fetch_url(ctx, url)

        timeout = aiohttp.ClientTimeout(total=30)

        async with aiohttp.ClientSession(
            timeout=timeout,
            auto_decompress=True,
        ) as session:
            async with session.get(
                target,
                allow_redirects=True,
            ) as response:

                # Read the ENTIRE response in chunks.
                chunks = []
                total_size = 0

                async for chunk in response.content.iter_chunked(64 * 1024):
                    if not chunk:
                        continue

                    total_size += len(chunk)

                    if total_size > MAX_FILE_SIZE:
                        raise ValueError(
                            "Response is larger than "
                            f"{MAX_FILE_SIZE // (1024 * 1024)} MB."
                        )

                    chunks.append(chunk)

                body = b"".join(chunks)

                final_url = str(response.url)
                status_code = response.status

                content_type = response.headers.get(
                    "Content-Type",
                    "application/octet-stream",
                )

        elapsed = (
            asyncio.get_running_loop().time()
            - started
        )

        # Decode the FULL response.
        source = body.decode(
            "utf-8",
            errors="replace",
        )

        source = redact_fetched_ips(source)

        resolved_name = Path(
            aiohttp.client_reqrep.URL(final_url).path
        ).name

        if resolved_name:
            stem = Path(resolved_name).stem
        else:
            stem = "script"

        stem = clean_filename(stem)

        if not stem:
            stem = "script"

        # ALWAYS .lua
        output_name = f"{stem}.lua"

        # Preview is the ONLY thing that gets shortened.
        preview = (
            "```lua\n"
            + oxygen_preview(
                source,
                1200,
            )
            + "\n```"
        )

        # Rubis receives FULL source.
        rubis = None

        try:
            rubis = await create_rubis_scrap(
                source,
                title=output_name,
            )
        except Exception as rubis_error:
            print(
                "[GET] Rubis upload failed:",
                repr(rubis_error),
            )

        raw_url = (
            rubis.get("raw")
            if rubis
            else None
        )

        view_url = (
            rubis.get("view")
            if rubis
            else None
        )

        accent = (
            discord.Color.green()
            if 200 <= status_code < 400
            else discord.Color.orange()
        )

        blocks = [
            (
                "Preview",
                preview,
            ),
            (
                "Response",
                f"`{len(body):,}` bytes • "
                f"`{len(source):,}` characters • "
                f"`{content_type}`",
            ),
            (
                "Request headers",
                "No Oxygen/Roblox/CORS-style custom headers were added.",
            ),
        ]

        if rubis is None:
            blocks.append(
                (
                    "Rubis",
                    "Rubis upload was unavailable. "
                    "The complete Lua source is still attached.",
                )
            )

        view = v2_card(
            "🔗 Oxygen GET",
            f"**HTTP {status_code}** • `{elapsed:.2f}s`\n"
            f"Resolved: `{trim(final_url, 500)}`",
            accent=accent,
            blocks=blocks,
            filename=output_name,
            raw_url=raw_url,
            view_url=view_url,
            source_url=final_url,
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        # IMPORTANT:
        # Do NOT use preview here.
        # Do NOT use oxygen_preview here.
        #
        # This is the COMPLETE fetched source.
        full_lua_file = io.BytesIO(
            source.encode("utf-8")
        )

        full_lua_file.seek(0)

        await send_v2(
            ctx,
            view,
            file=discord.File(
                full_lua_file,
                filename=output_name,
            ),
            reply=True,
        )

    except Exception as exc:
        view = v2_card(
            "❌ GET failed",
            "Oxygen could not fetch that resource.",
            accent=discord.Color.red(),
            blocks=[
                (
                    "Error",
                    "```text\n"
                    + trim(
                        type(exc).__name__
                        + ": "
                        + str(exc),
                        1700,
                    )
                    + "\n```",
                )
            ],
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    finally:
        if not ctx.interaction:
            await remove_reaction(
                ctx.message,
                "🔗",
            )

# ============================================================
# UPLOAD
# ============================================================

@bot.hybrid_command(
    name="upload",
    description="Upload Lua/text to Rubis and return raw + browser links.",
)
async def upload_command(
    ctx: commands.Context,
    attachment: discord.Attachment = None,
    *,
    source: str = None,
):
    if not await check_bot_access(ctx):
        return

    if ctx.interaction:
        await ctx.defer()
    else:
        await add_reaction(ctx.message, "📤")

    try:
        content, filename = await resolve_script_input(
            ctx,
            attachment=attachment,
            source=source,
        )

        rubis = await create_rubis_scrap(
            content,
            title=filename or "upload.lua",
        )

        if rubis is None:
            raise RuntimeError("Rubis did not return an upload link.")

        raw_url = rubis.get("raw")
        view_url = rubis.get("view")

        blocks = [
            (
                "Upload",
                f"`{len(content.encode('utf-8', errors='replace')):,}` bytes • `{filename}`",
            )
        ]

        if not view_url:
            blocks.append(("View in Browser", "Rubis did not return a browser-view URL."))

        view = v2_card(
            "📤 Uploaded to Rubis",
            "Your source was uploaded successfully.",
            accent=discord.Color.green(),
            blocks=blocks,
            raw_url=raw_url,
            view_url=view_url,
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    except Exception as exc:
        view = v2_card(
            "❌ Upload failed",
            "Could not upload that source to Rubis.",
            accent=discord.Color.red(),
            blocks=[
                (
                    "Error",
                    "```text\n"
                    + trim(type(exc).__name__ + ": " + str(exc), 1700)
                    + "\n```",
                )
            ],
            footer=f"Requested by {ctx.author} • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            reply=True,
        )

    finally:
        if not ctx.interaction:
            await remove_reaction(ctx.message, "📤")


# ============================================================
# CONFIG COMMAND
# ============================================================

@bot.hybrid_command(
    name="config",
    aliases=["cfg"],
    description="Configure the Roblox environment.",
)
@discord.app_commands.choices(
    executor_name=[
        discord.app_commands.Choice(
            name=name,
            value=name,
        )
        for name in EXECUTOR_NAMES
    ]
)
async def config_command(
    ctx: commands.Context,

    place_id: int = None,
    game_id: int = None,
    place_version: int = None,

    user_name: str = None,
    display_name: str = None,
    user_id: int = None,

    locale: str = None,
    membership_type: str = None,
    executor_name: str = None,
):
    if not await check_bot_access(
        ctx
    ):
        return

    updates = {
        "place_id": place_id,
        "game_id": game_id,
        "place_version": place_version,

        "user_name": user_name,
        "display_name": display_name,
        "user_id": user_id,

        "locale": locale,
        "membership_type": membership_type,
        "executor_name": executor_name,
    }

    if all(
        value is None
        for value in updates.values()
    ):
        profile = get_profile(
            ctx.author.id
        )

        view = v2_card(
            "⚙️ Oxygen Configuration",
            profile_summary(profile),
            accent=discord.Color.blurple(),
            footer="Settings are saved per user • Oxygen",
        )

        await send_v2(
            ctx,
            view,
            ephemeral=bool(ctx.interaction),
        )

        return

    if executor_name is not None:
        normalized_executor = normalize_executor_name(
            executor_name
        )

        if normalized_executor is None:
            view = v2_card(
                "❌ Invalid Executor",
                "Choose one of: "
                + ", ".join(
                    f"`{name}`"
                    for name in EXECUTOR_NAMES
                ),
                accent=discord.Color.red(),
                footer="Oxygen",
            )

            await send_v2(
                ctx,
                view,
                ephemeral=True,
            )
            return

        updates["executor_name"] = normalized_executor

    for key in (
        "place_id",
        "game_id",
        "place_version",
        "user_id",
    ):
        value = updates[key]

        if (
            value is not None
            and value < 0
        ):
            view = v2_card(
                "❌ Invalid Configuration",
                f"`{key}` cannot be negative.",
                accent=discord.Color.red(),
                footer="Oxygen",
            )

            await send_v2(
                ctx,
                view,
                ephemeral=True,
            )

            return

    profile = update_profile(
        ctx.author.id,
        updates,
    )

    view = v2_card(
        "✅ Configuration Saved",
        profile_summary(profile),
        accent=discord.Color.green(),
        footer="Settings are saved per user • Oxygen",
    )

    await send_v2(
        ctx,
        view,
        ephemeral=bool(ctx.interaction),
    )


# ============================================================
# HELP
# ============================================================

@bot.hybrid_command(
    name="help",
    description="Show Oxygen commands.",
)
async def help_command(
    ctx: commands.Context,
):
    if not await check_bot_access(ctx):
        return

    profile = get_profile(
        ctx.author.id
    )

    view = v2_card(
        "◈ Oxygen",
        "Run Lua in a fake Roblox client and read back what it did.",
        accent=discord.Color.from_rgb(
            88,
            101,
            242,
        ),
        blocks=[
            (
                "▸ Running scripts",
                "` .l ` — raw code, codeblock, URL, file, or reply.\n"
                "` .l --deep ` — deeper property tracing.\n"
                "` .get ` — fetch with Roblox-style profile headers.\n"
                "` .fetch ` — fetch Jnkie/HttpGet loaders without executing them.\n` .nexomiafp ` — set/show the Nexomia request fingerprint used by `.fetch`."
            ),
            (
                "▸ Deobfuscation",
                "` .deobfuscate ` — file, URL, reply, codeblock, or raw Lua.\n"
                "` .supported ` — available deobfuscation backends."
            ),
            (
                "▸ Making it yours",
                "` .cfg ` / ` .config ` — place, game, player, locale, "
                "membership, and executor identity.\n"
                f"Current executor: `{profile['executor_name']}` • "
                f"place: `{profile['place_id']}`"
            ),
            (
                "▸ If a script errors",
                "Oxygen keeps the partial log and shows the runtime "
                "error above the attached output."
            ),
            (
                "▸ Raw + attachments",
                "Text outputs are mirrored to a private Rubis scrap. "
                "The Discord attachment is rendered directly inside "
                "the Components v2 card."
            ),
        ],
        footer="◉ Settings are saved per user • Oxygen",
    )

    await send_v2(
        ctx,
        view,
        ephemeral=bool(ctx.interaction),
    )


# ============================================================
# STATUS
# ============================================================

statuses = [
    "Get wicked Get money",
    "From Sunday 2 Sunday",
    "Drink Remy I waddle",
    "Got the bands in pants don’t fall tho",
    "Shooter wear a mask no bane tho",
    "Shoot his face off now the case closed",
    "30 round clip don’t reload",
    "Skinny jeanz ya and they balmain",
    "Cartier frame keep me from the shade",
    "Summer time sip me up like lemonade",
    "Lately I been chillen on my solo",
    "Have u heard the news?",
]

status_index = 0


@discord_tasks.loop(
    seconds=2
)
async def rotate_status():
    global status_index

    await bot.change_presence(
        status=discord.Status.dnd,

        activity=discord.CustomActivity(
            name=statuses[
                status_index
            ]
        ),
    )

    status_index = (
        status_index + 1
    ) % len(statuses)


@rotate_status.before_loop
async def before_rotate_status():
    await bot.wait_until_ready()


# ============================================================
# READY
# ============================================================

@bot.event
async def on_ready():
    if not hasattr(discord.ui, "LayoutView"):
        print(
            "[Oxygen] Components v2 requires discord.py >= 2.6. "
            "Run: py -m pip install -U \"discord.py>=2.6\""
        )
    print(
        "=" * 65
    )

    print(
        (
            f"Oxygen online as "
            f"{bot.user} ({bot.user.id})"
        )
    )

    print(
        f"Free guild: {FREE_GUILD_ID}"
    )

    print(
        f"Paid guild: {PAID_GUILD_ID}"
    )

    print(
        f"Paid category: {PAID_CATEGORY_ID}"
    )

    print(
        f"Premium users: {len(paid_users)}"
    )

    print(
        f"IB1 command: {IB1_COMMAND}"
    )

    print(
        f"IB2 CLI: {IB2_CLI_PATH}"
    )

    print(
        (
            f"IB2 CLI exists: "
            f"{IB2_CLI_PATH.exists()}"
        )
    )

    print(
        f"Lune: {LUNE_PATH}"
    )

    print(
        "=" * 65
    )

    if not rotate_status.is_running():
        rotate_status.start()

    try:
        synced = await bot.tree.sync()

        print(
            (
                f"Synced {len(synced)} "
                "slash commands."
            )
        )

    except Exception as exc:
        print(
            "Slash sync failed:",
            exc,
        )


# ============================================================
# ERRORS
# ============================================================

@bot.event
async def on_command_error(
    ctx,
    error,
):
    if isinstance(
        error,
        commands.CommandNotFound,
    ):
        return

    original = getattr(
        error,
        "original",
        error,
    )

    print(
        (
            "[command error] "
            f"{type(original).__name__}: "
            f"{original}"
        )
    )

    try:
        await ctx.send(
            embed=deobf_embed(
                "Command Error",
                (
                    "```text\n"
                    f"{trim(original, 1500)}"
                    "\n```"
                ),
                discord.Color.red(),
            ),
            ephemeral=bool(
                ctx.interaction
            ),
        )

    except Exception:
        pass


# ============================================================
# TOKEN
# ============================================================

def get_bot_token():
    token = os.getenv(
        "BOT_TOKEN"
    )

    if token:
        return token

    if (
        shit is not None
        and hasattr(
            shit,
            "BOT_TOKEN",
        )
    ):
        return shit.BOT_TOKEN

    raise RuntimeError(
        (
            "Set BOT_TOKEN or provide "
            "shit.BOT_TOKEN"
        )
    )


# ============================================================
# START
# ============================================================

if __name__ == "__main__":
    bot.run(
        get_bot_token()
    )