<div align="center">

<img src="docs/banner.png" width="100%" alt="megab">

<br>

**A Roblox script hub with a hand-made glass UI.**
<br>
One line to run. It finds your game and loads the right features.

<br>

![Games](https://img.shields.io/badge/games-3-7c5cff?style=for-the-badge)
![Themes](https://img.shields.io/badge/themes-12-40c4ff?style=for-the-badge)
![Backgrounds](https://img.shields.io/badge/animated_backgrounds-4-00ff5f?style=for-the-badge)
![Icons](https://img.shields.io/badge/icons-Lucide-d97757?style=for-the-badge)
![Luau](https://img.shields.io/badge/Luau-2C2D72?style=for-the-badge&logo=lua&logoColor=white)

[⚡ Run it](#-run-it) • [🎮 Games](#-games) • [🎨 Themes](#-themes) • [✨ The UI](#-the-ui) • [❓ FAQ](#-faq)

</div>

---

## ⚡ Run it

Paste this into your executor and press **Execute**:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/aeveloy/megab/main/loader.lua"))()
```

That's the whole setup. 🎉

---

## 🧭 How to use it

| | Step | What happens |
|:-:|---|---|
| 1️⃣ | **Run** the line above | A loading screen fills up for about 2 seconds |
| 2️⃣ | **Pick a tab** on the left | Every feature is a switch, slider, dropdown, or button |
| 3️⃣ | **Hide it** with ✕ or `RightShift` | A small icon waits at the top center: click it to come back |
| 4️⃣ | **Make it yours** with ⚙️ | Pick a theme and your own open/close key |

> 💾 Your switches save **per game**. Your theme and key save for **every game**.

---

## 🎮 Games

| | Game | Highlights |
|:-:|---|---|
| 🔪 | **Murder Mystery 2** | Sheriff and murderer ESP · murderer alert · auto grab gun · coin farm |
| 🐾 | **Adopt Me!** | Auto pet needs · auto paycheck · teleport menu · anti-AFK |
| 🚔 | **Prison Life** | Team ESP · get guns · auto escape · noclip |

<details>
<summary><b>🔪 Murder Mystery 2: every feature</b></summary>
<br>

**Basic tab**
- 🔴🔵 **Sheriff and Murderer ESP**: murderer glows red, sheriff glows blue
- 🟢 **Everyone ESP**: innocents glow green, with names above heads
- 📏 **Display Distance**: role and distance in studs above murderer and sheriff
- 🟣 **Dropped Gun ESP**: highlights the gun after the sheriff dies
- 🔔 **Role Notify**: tells you who the murderer and sheriff are
- ⚠️ **Murderer Alert**: warns you when the murderer gets close (you pick the distance)
- 📍 **Teleports**: to the murderer, to the sheriff, or to any player you pick
- 🔫 **Auto Grab Gun**: grabs the dropped gun for you

**Farm tab**
- 🪙 **Coin ESP**: highlights every coin on the map
- 💰 **Coin Farm**: collects coins for you, at the speed you set

</details>

<details>
<summary><b>🐾 Adopt Me!: every feature</b></summary>
<br>

**Basic tab**
- 📍 **Teleport menu**: home, shops, and map spots in one dropdown
- 🏃 **Speed and jump** sliders
- 💤 **Anti-AFK**: no idle kick

**Farm tab**
- 💵 **Auto Paycheck**: collects your paycheck
- 🐶 **Auto Pet Needs**: finds what your pet needs and does it, including school, bed, bath, walk, ride, and play

</details>

<details>
<summary><b>🚔 Prison Life: every feature</b></summary>
<br>

**Basic tab**
- 👥 **Team ESP** with names and distance
- 📍 **Teleports** to the main places
- 🏃 **Speed, jump, and noclip**

**Guns tab**
- 🔫 **Get guns** from a dropdown, plus quick buttons for Remington and AK
- 🏃‍♂️ **Auto Escape**: inmate to criminal in one click

</details>

> 🌍 **In a game that isn't supported?** megab shows a tab for each supported game with a **Teleport** button, and loads itself again when you arrive.

---

## 🎨 Themes

12 themes. Colors fade smoothly when you switch, and every theme uses the glass look.

<div align="center">
<img src="docs/gallery.png" width="100%" alt="Code, Rain, Sakura, Forest, Sunset, and Midnight themes with their backgrounds">
</div>

<br>

| Theme | Background |
|---|---|
| 💻 **Code** | Matrix rain, animated |
| 🌧️ **Rain** | Rainy garden, animated |
| 🌸 **Sakura** | Cherry blossoms, animated |
| 🌿 **Forest** | Waterfall, animated |
| 🌅 **Sunset** | Golden sky that slowly drifts |
| 🌌 **Midnight** | Milky Way that slowly drifts |
| 🤖 **Claude · ChatGPT · Gemini** | Their logo, faint in the corner |
| ⚫ **Basic · Black · Light** | Plain glass |

<details>
<summary><b>🎨 See all 12 color sets</b></summary>
<br>
<div align="center">
<img src="docs/themes.png" width="100%" alt="The 12 megab themes">
</div>
</details>

---

## ✨ The UI

Built from scratch for megab, with no Rayfield or other UI library.

- 🪟 **Glass look**: see-through panels, a soft shine, and an outline that glows in the theme color
- 🧩 **Lucide icons** on tabs, buttons, and notifications
- 🌊 **Smooth animations**: the window bounces open, switches bounce, pages slide, and notifications fade
- 🎬 **Moving backgrounds**: GIFs turned into picture sheets and played inside Roblox
- 🖱️ **Drag it** by the top bar, or **minimize** it to just the title bar
- ⌨️ **Your own key** to open and close it
- 🔔 **Notifications** with an icon and a gradient outline

---

## ❓ FAQ

<details>
<summary><b>Which executors work?</b></summary>
<br>

Any executor with `loadstring` and `game:HttpGet`.
The backgrounds and logos also need `getcustomasset` and `writefile`. Without them you still get every feature, just without the pictures.
</details>

<details>
<summary><b>Where are my settings saved?</b></summary>
<br>

In your executor's `workspace/megab/` folder:
- `settings.json`: theme and key
- `configs/<GameId>.json`: your switches for each game
- `assets/`: background pictures, downloaded once the first time you pick a theme
</details>

<details>
<summary><b>The teleport says "blocked" or error 773?</b></summary>
<br>

Some games block teleports to other games. megab copies the game's link to your clipboard: paste it in your browser and join from there.
</details>

<details>
<summary><b>How do I close it for good?</b></summary>
<br>

**Info** tab → **Unload hub**. Running the loader again also replaces the old window, so you never get two.
</details>

<details>
<summary><b>🛠️ For developers: how do I add a game?</b></summary>
<br>

1. Create `games/<GameId>.lua` that returns `function(Window, ctx) ... end`
2. Add tabs with `Window:CreateTab({ name, icon })`, then `tab:CreateToggle / Slider / Dropdown / Button / Text`
3. Add the game to `SUPPORTED` in `loader.lua` and to the table above

The full rules are in [`CLAUDE.md`](CLAUDE.md).
</details>

---

<div align="center">

<img src="docs/logo.png" width="96" alt="megab logo">

### made by [@aeveloy](https://github.com/aeveloy) and claudecode <3

**#TEAMMEGAB** 💜

⭐ Star the repo if megab made your game better!

</div>
