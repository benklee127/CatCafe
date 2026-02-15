This document provides insight into the underlying purpose of everything we're doing here:
The Debrief: What We Are Building
The Concept: A cozy, single-player 2D management simulator where you run a foster cat cafe.
The Core Loop: Manage the "flow" of the cafe by placing strategic decor to keep cats from getting overstimulated by patrons.
The Progression: Rescue strays, rehabilitate their "Trust" meters, and adopt them out to the perfect patrons to earn Reputation and expand your cafe.
The Tech Stack: 2D Engine (Godot or Unity) + VS Code + strict data schemas for procedural generation.
The Business Model: Flat-fee Steam Direct launch ($100 to publish, no revenue sharing), driven by a TikTok/Reddit marketing funnel.
Here is your Foolproof Implementation Plan. This roadmap is designed to prevent "Feature Creep" (getting distracted by adding too many cool things before the base game works) and burnout.

Phase 1: The Foundation (Days 1-2)
Your goal here is strictly technical setup. Do not draw a single cat or write a single line of dialogue yet.

Install the Tools: Download your chosen engine and link it to VS Code.
Set Up Version Control (Crucial): Create a GitHub account and set up a repository. This makes the plan foolproof. If you completely break your game on a Tuesday, Git lets you click a button to revert the code back to how it was on Monday.
Folder Architecture: Build the exact blank folder structures we discussed earlier (Scenes, Scripts, Data, Art_Assets).
Phase 2: The "Ugly" Prototype (Weeks 1-2)
Your goal is to build the "Minimum Viable Product" (MVP). You will use literal gray squares and blue circles for art. If the game isn't fun with gray squares, it won't be fun with high-definition art.

Grid Movement: Make a script that allows you to click and snap a square "chair" to a 2D grid.
The Cat AI: Program a blue circle to wander randomly around the room.
The Core Mechanic: Write the logic so that when a green square (Patron) touches the blue circle (Cat), an Overstimulation variable goes up from 0 to 100. When it hits 100, the blue circle automatically paths to a designated "Rest Area" corner of the screen.
Phase 3: Systems and Data Integration (Weeks 3-4)
Once the ugly prototype is fun, you hook up the "brain" of the game.

The Databases: Build the JSON files or data dictionaries holding the Cat Traits, Patron Archetypes, and Decor Buffs.
The Proc-Gen Engine: Write the script that randomly pulls from those databases to spawn a unique cat with a random mix of traits.
The Math: Connect the data to the prototype. Now, the Overstimulation variable goes up faster or slower depending on the specific traits of the blue circle and green square.
Phase 4: The Vertical Slice (Months 2-3)
A "Vertical Slice" is a fully playable, polished version of just one level of your game.

Inject the Art: Replace the squares and circles with your actual 2D cozy pixel art or hand-drawn sprites.
The UI: Build the main menu, the settings menu, and the pop-up UI that shows the cats' stats.
The Adoption Loop: Code the logic that allows a player to click an "Adopt" button, permanently removing the cat from the cafe and adding +1 to the player's Reputation score.
Phase 5: The Content Grind (Months 3-5)
Once the Vertical Slice works perfectly, you just need more of it. This is where you put on your headphones and grind.

Draw 50 different pieces of furniture.
Add 5 different Patron archetypes.
Code the tactile mini-games (brushing, laser pointer).
Add the lo-fi background music and sound effects (purring, coffee pouring).
Phase 6: Marketing & The Steam Page (Month 5+)
You start this before the game is finished.

The Steam Page: Pay the $100 fee and set up your Steam page with screenshots from your Vertical Slice.
The Funnel: Start posting weekly devlogs on Reddit and short, aesthetic clips on TikTok/Shorts.
The Demo: Put your Vertical Slice on Itch.io for free to get real players to test it and find bugs you missed.
The Goal: Drive everyone from the Demo and Social Media to hit the "Wishlist" button on Steam.

Here is the master list of everything we have decided for your cozy cat cafe simulator:

1. Core Concept & Art Style
The Vibe: A relaxing, cozy management simulator with a strong heart, focused on resource management and animal rehabilitation.
Perspective: 2D Top-Down or Isometric (similar to Unpacking). This allows for a clean grid-based building system, highly readable UI, easy asset creation, and charming sprite animations without the headache of 3D modeling and physics.
2. The Cats (Procedural Generation & Traits)
Endless Variety: Cats are procedurally generated using 2D sprite layers (mixing coat patterns, fur length, eye colors, and tail types).
Distinct Personalities: Each cat rolls 2-3 traits (e.g., Cuddly, Feisty, Glutton) that dictate how fast they get overstimulated, how they interact with patrons, and what kind of "Forever Home" they need.
Rare Kitties: A small percentage chance to roll visually unique cats (e.g., Sphynx, Maine Coon) that provide massive passive buffs to the cafe.
3. The Core Loop: Overstimulation & Flow Management
The Overstimulation Bar: The central mechanic. As patrons pet and play with cats, this bar fills up. Different patrons fill it at different speeds (e.g., a Hyper Toddler spikes it, a Gentle Reader barely moves it).
Auto-Retreat State: When a cat hits 100% overstimulation, they automatically stop interacting and walk to the staff-only "Rest Area" to cool down.
The "Cat Drought": The main challenge for the player. If you let in too many energetic patrons, all your cats will retreat to the back room at once. An empty floor means angry patrons, bad reviews, and no tips.
4. The Narrative Heart: Fostering & Adopting
Sourcing Strays: You don't just buy cats; you rescue them. You can adopt from the Shelter (safe stats), search alleys (costs time, chance for Rares), or get "Doorstep Events" (random, terrified strays in boxes).
Rehabilitation: Strays start with a low "Trust Meter." By caring for them and keeping them stress-free, their Trust hits 100%, making them "Ready for Adoption."
Matchmaking: You match rehabilitated cats to regular patrons based on compatible traits. Successful adoptions are your primary way to earn "Reputation" to level up the cafe.
The VIP Alumni System: Adopted cats sometimes visit with their new owners! They have no overstimulation bar, emit a "Happy Tails" aura that calms other cats, and double your tips while they are there.
5. Tactical Decor & Cafe Upgrades
Tiered Progression: You use Reputation and Money to expand the cafe from a cramped single room (Tier 1) to a multi-room haven with a massive Rest Area (Tier 3).
Strategic Furniture: Decor isn't just cosmetic; it manipulates the gameplay flow.
Customer Decor: Velvet armchairs make patrons stay longer and spend more, but they hog the cats. Quick-serve espresso bars mean fast cash but low cat interaction.
Cat Decor: Wall shelves act as "mid-way rest stops" where cats can lower their overstimulation without leaving the floor. Heating pads boost happiness but make the cats sleep.
6. Hands-On Mini-Games
Purpose: Zooming in for tactile care breaks up the management gameplay and acts as your "Emergency Button" during a Cat Drought.
The Games: Brushing, nail trimming, or laser-pointer tracing.
The Reward: Perfectly executing a mini-game instantly clears a cat's overstimulation bar or gives a massive boost to a stray's Trust Meter, getting them back onto the cafe floor faster.

help me do a granular step by step implementation