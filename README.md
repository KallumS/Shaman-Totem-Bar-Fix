# Shaman Totem Bar Fix (WoW Forever 1.60.1)

In WoW Forever's beta GamePad UI, the Shaman totem bar (Call of the Elements, Call of the Ancestors and Call of the Spirits) doesn't appear. This addon adds its own copy of that bar, so you can pick the Fire, Earth, Water and Air totem for each Call spell without turning the GamePad UI off.

It doesn't change Blizzard's bar. It writes to the same server-side totem slots that Blizzard's bar uses. A totem you pick here is the one your Call spell drops, whether you cast it from this bar, from your gamepad action bar or from the normal UI.

## Install

1. Copy the `ShamanTotemBarFix` folder into your WoW Forever `Interface\AddOns` folder.
2. Restart the game, or type `/reload`.
3. On the character select screen, under AddOns, make sure **Shaman Totem Bar Fix** is enabled.

## Use

The bar is laid out like Blizzard's: `[Call] [Earth] [Fire] [Water] [Air] [Recall]`.

| Action | What it does |
|---|---|
| Arrow above **Call**, or right-click Call | Choose which set you're editing: Elements, Ancestors or Spirits |
| Left-click **Call** | Cast that Call spell |
| Arrow above a totem slot, or right-click it | Open the totem list for that slot (the top, empty entry clears the slot) |
| Left-click a totem slot | Cast that single totem |
| Left-click **Recall** | Totemic Recall |

You can't change totems during combat (Blizzard's bar has the same limit). An open list closes when combat starts.

By default the bar shows only while the GamePad UI is on. With the GamePad UI off, Blizzard's own bar works as normal.

## Commands (`/stbf` or `/totembar`)

| Command | Effect |
|---|---|
| `/stbf auto` | Show the bar only while the GamePad UI is on (default) |
| `/stbf show` / `/stbf hide` | Always show the bar / never show it |
| `/stbf unlock`, `/stbf lock` | Unlock the bar to drag it with the green box, then lock it |
| `/stbf scale 1.2` | Resize the bar (0.5 to 2) |
| `/stbf reset` | Return to the default position and scale |
| `/stbf set 1-3`, `/stbf next` | Switch to Elements, Ancestors or Spirits (works in a macro on a gamepad bar) |
| `/stbf debug` | Print the totem slots, for bug reports |
