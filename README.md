# Wayfinder

A directional HUD compass for WoW Forever, plus shared party waypoints, quest/flight/location tracking, and quick map pings.

## Compass HUD

An FPS-style compass strip across the top of the screen, scrolling cardinal letters and tick marks as you turn. Anything relevant on your current map shows up as an icon at its real bearing:

- **Party members** — portrait or class-color dot, your choice
- **Quest objectives** — every quest Blizzard attached position data to in your current zone. If your focused (super-tracked) quest is somewhere else, the compass shows its zone name instead of nothing — and if it's on the other continent, a quest icon points due west or east toward it, plus a live distance readout in yards once you're in the right zone
- **Flight points** — grey boot if you've already discovered it, green if you haven't
- **Auction houses, banks, mailboxes, innkeepers** — shown once you're within a configurable distance, since these are permanent fixtures in nearly every zone (mailboxes show only the nearest one, to avoid clutter in cities with several)
- **Your shared waypoints** — see below

Width, height, field of view, colors, and icon sizes are all configurable per element.

## Shared Waypoints

Mark a spot on the world map and it's automatically shared with your party:

- **Double-click** the map — permanent waypoint (stays until you remove it)
- **Alt+click** the map — temporary waypoint (expires after 15 minutes, can't be named)
- **Shift-click** a waypoint (on the map or compass) — remove it

Waypoints show on both the world map and the compass HUD, for you and everyone in your party.

## Pings

Quick, MOBA-style "look here" markers — `/wf ping` flashes a marker at your current position for your party to see for a few seconds, then it's gone. Nothing is saved.

## Settings

A full settings panel under **Options > AddOns > Wayfinder**, with independent Compass and Map sections — colors, opacity, icon sizes, and a show/hide toggle for every category of marker, on each surface separately.

## Slash Commands

```
/wf settings       - open the settings panel
/wf compass        - toggle the HUD compass
/wf quests         - toggle showing quest objectives
/wf ping           - send a ping at your current position
/wf wp temp        - add a 15-minute waypoint at your current position
/wf wp remove <name> - remove one of your waypoints by name
/wf wp clear       - remove all of your own waypoints
/wf wp wipeall     - remove every waypoint, including ones received from party
/wf list           - list every active waypoint, yours and your party's
```

A few `/wf ...check` commands print diagnostic info for quests/flight points/locations if something doesn't seem to be showing up right.

## Install

Drop the `Wayfinder` folder into `Interface/AddOns`.
