meta =
{
    -- ID of your mod; Make sure this is unique!
    -- Will be used for identifying the mod in dependency lists
    -- Will be changed to workshop ID (ensuring uniqueness) when you upload the mod to the workshop
    id = "gcl_tweaks",

    -- Name of your mod; You may want this to be unique, but it's not absolutely necessary.
    -- This is an additional helper attribute for you to easily identify your mod in the Mods() list
    name = "gcl_tweaks",

    -- Title of your mod that will be displayed to players
    title = "GCL Tweaks",

    -- Type of your mod, either "mod" or "factionpack"
    type = "mod",

    -- Description of your mod that will be displayed to players
    description =
    [[Provides utility commands for debugging and modifying game state.

    Commands:
    /gcl_tweak showdroptables - Print system upgrade drop weights
    /gcl_tweak isobjectwrecked - Check if entity has boarding malus (wrecked)
    /gcl_tweak setobjectwrecked 0|1 - Clear/set boarding malus]],

    -- Insert all authors into this list
    authors = { "luck2020" },

    -- Version of your mod, should be in format 1.0.0 (major.minor.patch) or 1.0 (major.minor)
    version = "1.0.0",

    -- Dependencies
    dependencies = {
    },

    -- Set to true if the mod only has to run on the server. Clients will get notified that the mod is running on the server, but they won't download it to themselves
    serverSideOnly = false,

    -- Set to true if the mod only has to run on the client, such as UI mods
    clientSideOnly = false,

    -- Set to true if the mod changes the savegame in a potentially breaking way
    -- This mod only adds commands, no persistent scripts on entities
    saveGameAltering = false,

    -- Contact info for other users to reach you in case they have questions
    contact = "GitHub",
}
